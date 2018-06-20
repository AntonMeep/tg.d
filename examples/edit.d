#!/usr/bin/env dub
/+
dub.json:
{
	"name": "edir",
	"descripton": "Simple bot which edits its own messages",
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
import tg.d           : TelegramBot;
import vibe.core.args : readRequiredOption;
import vibe.core.core : runApplication, setTimer, sleep;
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
				.each!((a) {
					auto m = Bot.sendMessage(a.message.chat.id, a.message.text);
					2.seconds.sleep;
					Bot.editMessageText(m.chat.id, m.id, "Hold on a moment, let me think about it");
					5.seconds.sleep;
					Bot.editMessageText(m.chat.id, m.id, "Nope, I don't think so");
				});
		},
		true); // To run this timer not just once, but every second

	"Running the bot".logInfo;
	return runApplication();
}

