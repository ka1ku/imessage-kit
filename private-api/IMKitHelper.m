// imessage-kit private API helper.
//
// Loaded into Messages.app (DYLD_INSERT_LIBRARIES; needs SIP off, library
// validation off and, on Apple Silicon, the -arm64e_preview_abi boot-arg).
// It dials the SDK's bridge on 127.0.0.1:$IMKIT_HELPER_PORT (Messages is
// sandboxed with network.client only, so the SDK listens and this connects)
// and answers newline-delimited JSON requests:
//
//   {"id":1,"op":"hello"}                                  → {"id":1,"ok":true,"version":1}
//   {"id":2,"op":"send","chat":"any;+;chat123","text":"hey Kai",
//    "mentions":[{"address":"+15551234567","start":4,"length":3}],
//    "effect":"com.apple.messages.effect.CKConfettiEffect"}
//                                                          → {"id":2,"ok":true,"guid":"…"}
//   {"id":3,"op":"nickname","handle":"+15551234567"}       → {"id":3,"ok":true,"name":"Kai"}
//
// Failures answer {"id":…,"ok":false,"error":"…"}. IMCore is private, so every
// selector is checked before use and a missing one is an error, not a crash.

#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

static const int VERSION = 1;
static const int DEFAULT_PORT = 45677;

// IMCore, declared just enough to call. Every call goes through `id`.
@interface NSObject (IMKitPrivate)
+ (id)sharedInstance;
- (id)existingChatWithGUID:(NSString *)guid;
- (id)existingChatWithChatIdentifier:(NSString *)identifier;
- (void)sendMessage:(id)message;
- (id)initWithSender:(id)sender time:(NSDate *)time text:(NSAttributedString *)text messageSubject:(NSAttributedString *)subject fileTransferGUIDs:(NSArray *)transfers flags:(unsigned long long)flags error:(NSError *)error guid:(NSString *)guid subject:(NSString *)subjectString balloonBundleID:(NSString *)balloon payloadData:(NSData *)payload expressiveSendStyleID:(NSString *)style;
- (NSString *)guid;
- (id)activeIMessageAccount;
- (id)imHandleWithID:(NSString *)handle;
- (id)nicknameForHandle:(id)handle;
- (NSString *)firstName;
- (NSString *)displayName;
@end

// What Messages.app sets on a typed, sent iMessage (as BlueBubbles' helper does).
static const unsigned long long MESSAGE_FLAGS = 100005;

static NSDictionary *fail(NSString *error) { return @{@"ok" : @NO, @"error" : error}; }

static id chatFor(NSString *guid) {
  id registry = [NSClassFromString(@"IMChatRegistry") sharedInstance];
  if (!registry) return nil;
  id chat = [registry existingChatWithGUID:guid];
  // chat.db says "any;+;chat…" on macOS 26 while IMCore may know it as "iMessage;+;chat…".
  if (!chat) chat = [registry existingChatWithChatIdentifier:[[guid componentsSeparatedByString:@";"] lastObject]];
  return chat;
}

static NSDictionary *sendText(NSDictionary *req) {
  NSString *guid = req[@"chat"], *text = req[@"text"];
  if (![guid isKindOfClass:NSString.class] || ![text isKindOfClass:NSString.class] || !text.length) return fail(@"send needs chat and text");
  id chat = chatFor(guid);
  if (!chat) return fail([NSString stringWithFormat:@"no chat %@", guid]);

  NSMutableAttributedString *body = [[NSMutableAttributedString alloc] initWithString:text];
  [body addAttribute:@"__kIMMessagePartAttributeName" value:@0 range:NSMakeRange(0, text.length)];
  for (NSDictionary *m in req[@"mentions"] ?: @[]) {
    NSUInteger start = [m[@"start"] unsignedIntegerValue], length = [m[@"length"] unsignedIntegerValue];
    NSString *address = m[@"address"];
    if (![address isKindOfClass:NSString.class] || !length || start + length > text.length) return fail(@"bad mention range");
    [body addAttribute:@"__kIMMentionConfirmedMention" value:address range:NSMakeRange(start, length)];
  }

  id message = [NSClassFromString(@"IMMessage") alloc];
  SEL init = @selector(initWithSender:time:text:messageSubject:fileTransferGUIDs:flags:error:guid:subject:balloonBundleID:payloadData:expressiveSendStyleID:);
  if (![message respondsToSelector:init]) return fail(@"IMMessage init selector missing on this macOS");
  NSString *effect = [req[@"effect"] isKindOfClass:NSString.class] ? req[@"effect"] : nil;
  message = [message initWithSender:nil time:nil text:body messageSubject:nil fileTransferGUIDs:nil flags:MESSAGE_FLAGS error:nil guid:nil subject:nil balloonBundleID:nil payloadData:nil expressiveSendStyleID:effect];
  [chat sendMessage:message];
  return @{@"ok" : @YES, @"guid" : [message guid] ?: NSNull.null};
}

// The name a person shares with their iMessage profile ("Share Name and Photo"), if they shared it with us.
static NSDictionary *nickname(NSDictionary *req) {
  NSString *handleID = req[@"handle"];
  if (![handleID isKindOfClass:NSString.class]) return fail(@"nickname needs handle");
  id account = [[NSClassFromString(@"IMAccountController") sharedInstance] activeIMessageAccount];
  id handle = [account imHandleWithID:handleID];
  id controller = [NSClassFromString(@"IMNicknameController") sharedInstance];
  if (!handle || ![controller respondsToSelector:@selector(nicknameForHandle:)]) return @{@"ok" : @YES, @"name" : NSNull.null};
  id nick = [controller nicknameForHandle:handle];
  NSString *name = [nick respondsToSelector:@selector(firstName)] ? [nick firstName] : nil;
  if (!name.length && [nick respondsToSelector:@selector(displayName)]) name = [nick displayName];
  return @{@"ok" : @YES, @"name" : name.length ? name : NSNull.null};
}

static NSDictionary *route(NSDictionary *req) {
  NSString *op = req[@"op"];
  if ([op isEqual:@"hello"]) return @{@"ok" : @YES, @"version" : @(VERSION)};
  if ([op isEqual:@"send"]) return sendText(req);
  if ([op isEqual:@"nickname"]) return nickname(req);
  return fail([NSString stringWithFormat:@"unknown op %@", op]);
}

static NSData *answer(NSData *line) {
  NSDictionary *req = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
  __block NSDictionary *res;
  if (![req isKindOfClass:NSDictionary.class]) {
    res = fail(@"bad json");
  } else {
    // IMCore is main-thread only.
    dispatch_sync(dispatch_get_main_queue(), ^{
      @try {
        res = route(req);
      } @catch (NSException *e) {
        res = fail([NSString stringWithFormat:@"%@: %@", e.name, e.reason]);
      }
    });
    NSMutableDictionary *withId = [res mutableCopy];
    withId[@"id"] = req[@"id"] ?: NSNull.null;
    res = withId;
  }
  NSMutableData *out = [[NSJSONSerialization dataWithJSONObject:res options:0 error:nil] mutableCopy];
  [out appendBytes:"\n" length:1];
  return out;
}

static BOOL writeAll(int fd, NSData *data) {
  const char *p = data.bytes;
  size_t left = data.length;
  while (left) {
    ssize_t n = write(fd, p, left);
    if (n <= 0) return NO;
    p += n, left -= (size_t)n;
  }
  return YES;
}

static void serve(int fd) {
  NSMutableData *buffer = [NSMutableData data];
  char chunk[65536];
  for (;;) {
    ssize_t n = read(fd, chunk, sizeof chunk);
    if (n <= 0) return;
    [buffer appendBytes:chunk length:(NSUInteger)n];
    for (;;) {
      NSRange nl = [buffer rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buffer.length)];
      if (nl.location == NSNotFound) break;
      NSData *line = [buffer subdataWithRange:NSMakeRange(0, nl.location)];
      [buffer replaceBytesInRange:NSMakeRange(0, nl.location + 1) withBytes:NULL length:0];
      @autoreleasepool {
        if (line.length && !writeAll(fd, answer(line))) return;
      }
    }
  }
}

// Keeps dialing the SDK; it may start before or after Messages, and restarts.
static void dial(int port) {
  for (;;) {
    @autoreleasepool {
      int fd = socket(AF_INET, SOCK_STREAM, 0);
      struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons((uint16_t)port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
      if (fd >= 0 && connect(fd, (struct sockaddr *)&addr, sizeof addr) == 0) {
        NSLog(@"[imessage-kit helper] connected to 127.0.0.1:%d", port);
        serve(fd);
        NSLog(@"[imessage-kit helper] disconnected");
      }
      if (fd >= 0) close(fd);
    }
    sleep(1);
  }
}

__attribute__((constructor)) static void start(void) {
  if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.MobileSMS"]) return;
  int port = [NSProcessInfo.processInfo.environment[@"IMKIT_HELPER_PORT"] intValue] ?: DEFAULT_PORT;
  NSLog(@"[imessage-kit helper] v%d loaded", VERSION);
  [NSThread detachNewThreadWithBlock:^{
    dial(port);
  }];
}
