#!/usr/bin/env dub
/+
dub.json:
{
	"name": "echo",
	"descripton": "Simple bot which just sends user's messages back",
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
import vibe.core.core : runApplication, setTimer;
import vibe.core.log  : logInfo;

int main() {
	auto Bot = TelegramBot(
		"token|t".readRequiredOption!string("Bot token to use. Ask Botfather for it")
	);

	"This bot info: %s".logInfo(Bot.getMe);

	"Setting up the timer".logInfo;
	1.seconds.setTimer(
		() {
			Bot.updateGetter
				.tee!( a => Bot.sendMessage(a.message.chat.id, a.message.text))
				.each!(a =>
					"Message sent back to user %s: `%s`".logInfo(a.message.from.first_name, a.message.text));
		},
		true); // To run this timer not just once, but every second

	"Running the bot".logInfo;
	return runApplication();
}

