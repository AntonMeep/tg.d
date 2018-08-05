#!/usr/bin/env dub
/+
dub.json:
{
	"name": "buttons",
	"descripton": "Simple bot which shows inline buttons",
	"license": "Public Domain",
	"dependencies": {
		"tg-d": {"path": "../"}
	}
}
+/

import core.time      : seconds;
import tg.d;
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
				if(!update.callback_query.isNull) {
					"Answering callback query".logInfo;
					Bot.answerCallbackQuery(update.callback_query.id);
					Bot.sendMessage(update.callback_query.message.chat.id, "Done!");
				} else if(!update.message.isNull) {
					InlineKeyboardButton button_url = {
						text: "Visit repository",
						url: "https://gitlab.com/ohboi/tg.d",
					};

					InlineKeyboardButton button_action = {
						text: "Do something",
						callback_data: "blablabla",
					};

					SendMessageMethod m = {
						chat_id: update.message.chat.id,
						text: "Look at these buttons!",
						reply_markup: InlineKeyboardMarkup([
							[button_url, button_action],
						]),
					};
					Bot.sendMessage(m);
				}
			}
		},
		true); // To run this timer not just once, but every second

	"Running the bot".logInfo;
	return runApplication();
}
