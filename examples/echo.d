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
	},
	"subConfigurations": {
		"tg-d": "verbose_openssl-1.1"
	}
}
+/

import core.time : seconds;

import tg.d;
import vibe.core.args;
import vibe.core.core;
import vibe.core.log;
import std.algorithm;
import std.range;

int main() {
	(cast(FileLogger) getLoggers[0]).useColors = false;
	LogLevel.debug_.setLogLevel;

	auto Bot = TelegramBot(
		"token|t".readRequiredOption!string("Bot token to use. Ask Botfather for it")
	);

	"This bot info: %s".logInfo(Bot.getMe);

	"Setting up the timer".logInfo;
	1.seconds.setTimer(
		() => Bot.updateGetter
				 // First, print the info about what user sent to the bot
				 .tee!( a => "User %s sent `%s`".logInfo(a.message.from.first_name, a.message.text))
				 // Second, reply to the user
				 .tee!( a => Bot.sendMessage(a.message.chat.id, a.message.text))
				 .each!(a => "Message sent back to user".logInfo),
		true); // To run this timer not just once, but every second

	"Running the bot".logInfo;
	return runApplication();
}