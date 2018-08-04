#!/usr/bin/env dub
/+
dub.json:
{
	"name": "edit",
	"descripton": "Simple bot which edits its own messages",
	"license": "Public Domain",
	"dependencies": {
		"tg-d": {"path": "../"}
	}
}
+/

import core.time      : seconds;
import tg.d           : TelegramBot;
import vibe.core.args : readRequiredOption;
import vibe.core.core : runApplication, setTimer, sleep, runTask;
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

	"Setting up the timer".logInfo;
	1.seconds.setTimer(
		() {
			foreach(update; Bot.updateGetter) {
				runTask({
					auto sent = Bot.sendMessage(update.message.chat.id, update.message.text);
					2.seconds.sleep;
					Bot.editMessageText(sent.chat.id, sent.id, "Hold on a moment, let me think about it");
					5.seconds.sleep;
					Bot.editMessageText(sent.chat.id, sent.id, "Nope, I don't think so");
				});
			}
		},
		true); // To run this timer not just once, but every second

	"Running the bot".logInfo;
	return runApplication();
}

