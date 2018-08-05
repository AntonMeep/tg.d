#!/usr/bin/env dub
/+
dub.json:
{
	"name": "reply",
	"descripton": "Simple bot which just replies to user's messages",
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
		{
			foreach(update; Bot.updateGetter) {
				if(update.message.isNull)
					continue; // Skipping other kinds of updates
				Bot.sendMessage(update.message.chat.id, update.message.id, "Oh, do you really mean it? It's so nice of you!");
				"Replied to user %s who wrote `%s`".logInfo(update.message.from.first_name, update.message.text);
			}
		},
		true); // To run this timer not just once, but every second

	"Running the bot".logInfo;
	return runApplication();
}
