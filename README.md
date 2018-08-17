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

Data structures such as `Update`, `Message` and others have `isNull` property which can be used to check if field has a value:
```D
if(!update.message.isNull) {
	// Update is a message
} else if(!update.edited_message.isNull) {
	// Update is a edited message
} else ...
```

## Examples

Are in the `examples` directory:

| name | description |
|------|-------------|
| [action.d](examples/action.d) | Shows all kinds of actions that bot can broadcast to users (for example: `... typing`, `... sending photo`)
| [buttons.d](examples/buttons.d) | Sends messages with attached inline keyboard |
| [echo.d](examples/echo.d) | Sends user's messages back |
| [edit.d](examples/edit.d) | Edits own messages |
| [livelocation.d](examples/livelocation.d) | Sends location and updates it |
| [reply.d](examples/reply.d) | Replies to user's messages |
| [sendthings.d](examples/sendthings.d) | Sends photos, videos, audio files, locations, venues and other kinds of data |