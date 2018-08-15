#!/usr/bin/env dub
/+
dub.json:
{
	"name": "action",
	"descripton": "Simple bot which shows all kinds of chat actions",
	"license": "Public Domain",
	"dependencies": {
		"tg-d": {"path": "../"}
	}
}
+/

import core.time      : seconds;
import tg.d           : TelegramBot, ChatAction;
import vibe.core.args : readRequiredOption;
import vibe.core.core : runApplication, sleep, runTask;
import vibe.core.log  : logInfo;

int main() {
	auto Bot = TelegramBot(
		"token|t".readRequiredOption!string("Bot token to use. Ask BotFather for it")
	);

	auto me = Bot.getMe;
	"This bot info:"     .logInfo;
	"\tID: %d"           .logInfo(me.id);
	"\tIs bot: %s"       .logInfo(me.is_bot);
	"\tFirst name: %s"   .logInfo(me.first_name);
	"\tLast name: %s"    .logInfo(me.last_name);
	"\tUsername: %s"     .logInfo(me.username);
	"\tLanguage code: %s".logInfo(me.language_code);

	runTask({
		while(true) {
			foreach(update; Bot.pollUpdates) {
				runTask({
					Bot.sendMessage(update.message.chat.id, "Typing");
					1.seconds.sleep;
					Bot.sendChatAction(update.message.chat.id, ChatAction.typing);
					3.seconds.sleep;

					Bot.sendMessage(update.message.chat.id, "Uploading photo");
					1.seconds.sleep;
					Bot.sendChatAction(update.message.chat.id, ChatAction.upload_photo);
					3.seconds.sleep;

					Bot.sendMessage(update.message.chat.id, "Recording video");
					1.seconds.sleep;
					Bot.sendChatAction(update.message.chat.id, ChatAction.record_video);
					3.seconds.sleep;

					Bot.sendMessage(update.message.chat.id, "Uploading video");
					1.seconds.sleep;
					Bot.sendChatAction(update.message.chat.id, ChatAction.upload_video);
					3.seconds.sleep;

					Bot.sendMessage(update.message.chat.id, "Recording audio");
					1.seconds.sleep;
					Bot.sendChatAction(update.message.chat.id, ChatAction.record_audio);
					3.seconds.sleep;

					Bot.sendMessage(update.message.chat.id, "Uploading audio");
					1.seconds.sleep;
					Bot.sendChatAction(update.message.chat.id, ChatAction.upload_audio);
					3.seconds.sleep;

					Bot.sendMessage(update.message.chat.id, "Uploading document");
					1.seconds.sleep;
					Bot.sendChatAction(update.message.chat.id, ChatAction.upload_document);
					3.seconds.sleep;

					Bot.sendMessage(update.message.chat.id, "Finding location");
					1.seconds.sleep;
					Bot.sendChatAction(update.message.chat.id, ChatAction.find_location);
					3.seconds.sleep;

					Bot.sendMessage(update.message.chat.id, "Recording video note");
					1.seconds.sleep;
					Bot.sendChatAction(update.message.chat.id, ChatAction.record_video_note);
					3.seconds.sleep;

					Bot.sendMessage(update.message.chat.id, "Uploading video note");
					1.seconds.sleep;
					Bot.sendChatAction(update.message.chat.id, ChatAction.upload_video_note);
				});
			}
		}
	});

	return runApplication();
}

