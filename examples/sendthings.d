#!/usr/bin/env dub
/+
dub.json:
{
	"name": "sendthings",
	"descripton": "Telegram bot with multiple commands for sending random photos, audios, etc",
	"license": "Public Domain",
	"dependencies": {
		"tg-d": {"path": "../"},
		"vibe-d:http": "~>0.8",
		"vibe-d:tls": "~>0.8",
	},
	"subConfigurations": {
		"vibe-d:tls": "openssl-1.1"
	}
}
+/

/**
 * This example is powered by:
 * - https://loremflickr.com
 * - https://freemusicarchive.org
 * - https://archive.org
 * - https://commons.wikimedia.org
 * All rights for videos, photos and animations used in this example go to their respective owners.
 */

import core.time        : seconds;
import std.algorithm    : startsWith;
import std.format       : format;
import std.random       : uniform, choice;
import tg.d;
import vibe.core.args   : readRequiredOption;
import vibe.core.core   : runApplication, runTask;
import vibe.core.log    : logInfo;
import vibe.http.client : requestHTTP;

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
	runTask({
		while(true) {
			foreach(update; Bot.pollUpdates) {
				if(update.message.isNull || !update.message.text.length) // We are only caring about text messages
					continue;

				if(update.message.text.startsWith("/photo")) {
					"Got /photo command, sending random photo".logInfo;
					Bot.sendPhoto(
						update.message.chat.id,
						"https://loremflickr.com/320/240/dog,puppy?random=%d".format(uniform(0, int.max))
					);
				} else if(update.message.text.startsWith("/audio")) {
					"Got /audio command, sending random audio".logInfo;

					SendAudioMethod m = {
						chat_id: update.message.chat.id,
					};

					"https://freemusicarchive.org/featured.json".requestHTTP(
						(scope req) {},
						(scope res) {
							auto j = res.readJson["aTracks"];
							auto track = j[].choice;
		
							m.audio      = track["track_file_url"].get!string;
							m.performer  = track["artist_name"].get!string;
							m.title      = track["track_title"].get!string;
							m.thumb      = track["track_image_file"].get!string;
							m.caption    = "Licensed under the terms of [%s](%s) license".format(
								track["license_title"].get!string,
								track["license_url"].get!string,
							);
							m.parse_mode = ParseMode.markdown;
						}
					);

					Bot.sendAudio(m);
				} else if(update.message.text.startsWith("/document")) {
					"Got /document command, sending D specification".logInfo;

					Bot.sendDocument(update.message.chat.id, "https://dlang.org/dlangspec.pdf");
				} else if(update.message.text.startsWith("/video")) {
					"Got /video command, sending the train".logInfo;

					Bot.sendVideo(
						update.message.chat.id, 
						"https://archive.org/download/youtube--e1u7Fgoocc/L_Arrivee_D_un_Train_En_Gare_De_La_Ciotat_1895--e1u7Fgoocc.mp4"
					);
				} else if(update.message.text.startsWith("/animation")) {
					"Got /animation command, sending an animation".logInfo;

					SendAnimationMethod m = {
						chat_id: update.message.chat.id,
						animation: "https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif",
						caption: "By Marvel (Based upon a NASA image, see [1].) [GFDL](http://www.gnu.org/copyleft/fdl.html) or [CC-BY-SA-3.0](http://creativecommons.org/licenses/by-sa/3.0/), via Wikimedia Commons",
						parse_mode: ParseMode.markdown,
					};
					Bot.sendAnimation(m);
				} else if(update.message.text.startsWith("/location")) {
					"Got /location command, sending random location".logInfo;

					Bot.sendLocation(update.message.chat.id, uniform(0.0f, 90.0f), uniform(-180.0f, 180.0f));
				} else if(update.message.text.startsWith("/venue")) {
					"Got /venue command, sending random venue".logInfo;

					Bot.sendVenue(update.message.chat.id, uniform(0.0f, 90.0f), uniform(-180.0f, 180.0f), "The Void", "Void st.");
				} else if(update.message.text.startsWith("/contact")) {
					"Got /contact command, sending fictional number".logInfo;

					Bot.sendContact(update.message.chat.id, "555-0100", "Fictional Number");
				} else if(update.message.text.startsWith("/action")) {
					"Got /action command, pretending to be typing something".logInfo;

					Bot.sendChatAction(update.message.chat.id, "typing");
				} else {
					Bot.sendMessage(update.message.chat.id, "What do you mean by that?");
				}
			}
		}
	});

	return runApplication();
}
