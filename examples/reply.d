#!/usr/bin/env dub
/+
dub.json:
{
	"name": "reply",
	"descripton": "Simple bot which just replies to user's messages",
	"authors": [
		"Anton Fediushin"
	],
	"copyright": "Copyright © 2018, Anton Fediushin",
	"license": "MIT",
	"dependencies": {
		"tg-d": {"path": "../"}
	}
}
+/

import core.time      : seconds;
import std.algorithm  : each;
import std.range      : tee;
import tg.d           : TelegramBot, SendMessageMethod;
import vibe.core.args : readRequiredOption;
import vibe.core.core : runApplication, setTimer;
import vibe.core.log  : logInfo;

int main() {
	auto Bot = TelegramBot(
		"token|t".readRequiredOption!string("Bot token to use. Ask Botfather for it")
	);

	auto me = Bot.getMe;
	"This bot info:"     .logInfo;
	"\tID: %d"           .logInfo(me.id);
	"\tIs bot: %s"       .logInfo(me.is_bot);
	"\tFirst name: %s"   .logInfo(me.first_name);
	"\tLast name: %s"    .logInfo(me.last_name.isNull     ? "null" : me.last_name);
	"\tUsername: %s"     .logInfo(me.username.isNull      ? "null" : me.username);
	"\tLanguage code: %s".logInfo(me.language_code.isNull ? "null" : me.language_code);

	"Setting up the timer".logInfo;
	1.seconds.setTimer(
		() {
			Bot.updateGetter
				.tee!( a =>
					Bot.sendMessage(a.message.chat.id, a.message.id, "Oh, do you really mean it? It's so nice of you!"))
				.each!(a =>
					"Replied to user %s who wrote `%s`".logInfo(a.message.from.first_name, a.message.text));
		},
		true); // To run this timer not just once, but every second

	"Running the bot".logInfo;
	return runApplication();
}
