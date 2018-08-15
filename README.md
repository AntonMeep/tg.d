tg.d [![pipeline status](https://gitlab.com/ohboi/tg.d/badges/master/pipeline.svg)](https://gitlab.com/ohboi/tg.d/pipelines)[![coverage report](https://gitlab.com/ohboi/tg.d/badges/master/coverage.svg)](https://gitlab.com/ohboi/tg.d/pipelines)
========

**tg.d** is a Telegram Bot API client implementation built to make fast and safe bots with the help of the D programming language.

## Documentation

API reference is available [here](ohboi.gitlab.io/tg.d).

## Getting updates

Currently, only long polling is supported. Use [`TelegramBot.pollUpdates`](https://ohboi.gitlab.io/tg.d/tg/d/TelegramBot.pollUpdates.html) which provides high-level abstraction over [`TelegramBot.getUpdates`](https://ohboi.gitlab.io/tg.d/tg/d/TelegramBot.getUpdates.html).

```D
import tg.d;

void main() {
	while(true) {
		foreach(update; TelegramBot("token").pollUpdates) {
			// Do something with `update`
		}
	}
}
```

Notice that everything is done in `while(true)` loop. It's possible because [`TelegramBot.pollUpdates`](https://ohboi.gitlab.io/tg.d/tg/d/TelegramBot.pollUpdates.html) defines timeout of 3 seconds by default which means that it'll block the running thread for 3-ish seconds.