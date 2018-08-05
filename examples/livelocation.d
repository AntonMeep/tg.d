#!/usr/bin/env dub
/+
dub.json:
{
	"name": "sendthings",
	"descripton": "Telegram bot which sends a location and updates it",
	"license": "Public Domain",
	"dependencies": {
		"tg-d": {"path": "../"}
	}
}
+/

import core.time        : seconds;
import tg.d;
import vibe.core.args   : readRequiredOption;
import vibe.core.core   : runApplication, setTimer, runTask, sleep;
import vibe.core.log    : logInfo;

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
				if(update.message.isNull)
					continue; // We are only interested in message updates
				runTask({ // It is necessary to do `runTask` here, because `sleep` is used here to make
						  // a delay between `editMessageLiveLocation` calls which will block every task
						  // for 30 seconds

					SendLocationMethod m = {
						chat_id: update.message.chat.id,
						latitude: 41.9f,
						longitude: 12.5f,
						live_period: 60,
					};

					auto sent = Bot.sendLocation(m); // ID of the sent message is required to edit it
					foreach(i; 0..10) {
						3.seconds.sleep;

						"Updating location".logInfo;
						Bot.editMessageLiveLocation(sent.chat.id,
													sent.message_id,
													m.latitude += 0.0001f,
													m.longitude += 0.0001f);
					}

					"Stopping live location".logInfo;
					Bot.stopMessageLiveLocation(sent.chat.id, sent.message_id);
				});
			}
		},
		true); // To run this timer not just once, but every second

	"Running the bot".logInfo;
	return runApplication();
}

