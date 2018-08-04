#!/usr/bin/env dub
/+
dub.json:
{
	"name": "echo",
	"descripton": "Simple bot which just sends user's messages back",
	"license": "Public Domain",
	"dependencies": {
		"tg-d": {"path": "../"}
	}
}
+/

import core.time      : seconds;
import tg.d           : TelegramBot;
import vibe.core.args : readRequiredOption;
import vibe.core.core : runApplication, setTimer;
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
				Bot.sendMessage(update.message.chat.id, update.message.text);
				"Message sent back to user %s: `%s`".logInfo(update.message.from.first_name, update.message.text);
			}
		},
		true); // To run this timer not just once, but every second

	"Running the bot".logInfo;
	return runApplication();
}

