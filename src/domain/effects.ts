/**
 * iMessage effect names → the expressiveSendStyleID Messages.app sends.
 */

import type { MessageEffect } from '../types/send'

export const EFFECT_STYLE_IDS: Record<MessageEffect, string> = {
    confetti: 'com.apple.messages.effect.CKConfettiEffect',
    fireworks: 'com.apple.messages.effect.CKFireworksEffect',
    balloons: 'com.apple.messages.effect.CKHappyBirthdayEffect',
    celebration: 'com.apple.messages.effect.CKSparklesEffect',
    lasers: 'com.apple.messages.effect.CKLasersEffect',
    love: 'com.apple.messages.effect.CKHeartEffect',
    spotlight: 'com.apple.messages.effect.CKSpotlightEffect',
    echo: 'com.apple.messages.effect.CKEchoEffect',
    slam: 'com.apple.MobileSMS.expressivesend.impact',
    loud: 'com.apple.MobileSMS.expressivesend.loud',
    gentle: 'com.apple.MobileSMS.expressivesend.gentle',
    invisibleInk: 'com.apple.MobileSMS.expressivesend.invisibleink',
}
