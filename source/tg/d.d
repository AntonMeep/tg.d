/**
 * Tg.d is a D client library for Telegram Bot API
 *
 * Authors: Anton Fediushin, Pavel Chebotarev
 * Licence: MIT, see LICENCE
 * Copyright: Copyright for portions of project tg.d are held by Pavel Chebotarev, 2018 as part of project telega (https://github.com/nexor/telega). All other copyright for project tg.d are held by Anton Fediushin, 2018.
 * See_Also: $(LINK https://gitlab.com/ohboi/tg.d)
 */
module tg.d;

import std.math : isNaN;

import vibe.core.log;
import vibe.data.json : Json;

import std.meta : AliasSeq, staticIndexOf;

version(unittest) import fluent.asserts;

version(TgD_Verbose)
	pragma(msg, "tg.d | Warning! tg.d is compiled in verbose mode, user data can end up in logs. DISABLE THIS IN PRODUCTION BUILDS");


/**
 * An exception thrown by tg.d on errors
 */
class TelegramBotException : Exception {
	/**
	 * Telegram Bot API error code
	 *
	 * Doesn't mean anything useful, meaning may change in the future
	 * See_Also: $(LINK https://core.telegram.org/bots/api#making-requests)
	 */
	ushort code;

	/// Constructor
	this(ushort code, string description, string file = __FILE__,
			size_t line = __LINE__, Throwable next = null) @nogc @safe pure nothrow {
		this.code = code;
		super(description, file, line, next);
	}
}

/**
 * Main structure representing one bot
 */
struct TelegramBot {
@trusted:
	private {
		string m_url;

		struct MethodResult(T) {
			bool ok;
		@optional:
		@optional:
			T result;
			ushort error_code;
			string description;
		}

		version(unittest) Json delegate(string, Json) @safe m_fakecall;
	}
	/**
	 * Create a new bot using token
	 *
	 * To obtain a new token ask $(LINK2 https://core.telegram.org/bots#botfather, BotFather).
	 * Params:
	 *     token = Telegram bot token
	 */
	this(string token) {
		this.m_url = "https://api.telegram.org/bot" ~ token;
	}

	version(unittest) {
		this(string token, Json delegate(string, Json) @safe fakecall) {
			this.m_url = "https://api.telegram.org/bot" ~ token;
			m_fakecall = fakecall;
		}

		private T callMethod(T, M)(M method) {
			auto json = m_fakecall(m_url ~ method.m_path, method.serializeToJson).deserializeJson!(MethodResult!T);

			if(!json.ok)
				throw new TelegramBotException(json.error_code, json.description);

			return json.result;
		}
	} else {
		private T callMethod(T, M)(M method) {
			import vibe.http.client : requestHTTP, HTTPMethod;
			T result;

			debug "tg.d | Requesting %s".logDebugV(method.m_path);

			requestHTTP(m_url ~ method.m_path,
				(scope req) {
					req.method = HTTPMethod.POST;

					Json j = method.serializeToJson;

					debug version(TgD_Verbose) "tg.d | Sending body: %s".logDebugV(j);
					req.writeJsonBody(j);
				},
				(scope res) {
					auto answer = res.readJson;
					debug version(TgD_Verbose) "tg.d | Response data: %s".logDebugV(answer);

					auto json = answer.deserializeJson!(MethodResult!T);

					if(!json.ok)
						throw new TelegramBotException(json.error_code, json.description);

					result = json.result;
				}
			);

			return result;
		}
	}

	/**
	 * Receive incoming updates using long polling
	 *
	 * Params:
	 *     offset          = Identifier of the first update to be returned
	 *     limit           = Limits the number of updates to be retrieved
	 *     timeout         = Timeout in seconds for long polling
	 *                       Should be positive, short polling (timeout == 0) should be used for testing purposes only.
	 *     allowed_updates = List the types of updates you want your bot to receive
	 * Returns: An array of updates
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `GetUpdatesMethod`, $(LINK https://core.telegram.org/bots/api#getupdates)
	 */
	Update[] getUpdates(int offset = 0, int limit = 100, int timeout = 3, string[] allowed_updates = []) {
		GetUpdatesMethod m = {
			offset: offset,
			limit: limit,
			timeout: timeout,
			allowed_updates: allowed_updates,
		};

		return getUpdates(m);
	}

	/// ditto
	Update[] getUpdates(GetUpdatesMethod m) {
		return callMethod!(Update[])(m);
	}

	@("getUpdates()")
	unittest {
		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/getUpdates");
				data.should.be.equal(
					Json([
						"limit": Json(100),
						"timeout": Json(3),
					])
				);

				return Json([
					"ok": Json(true),
					"result": Json.emptyArray,
				]);
			}
		).getUpdates.length.should.be.equal(0);
	}

	/**
	 * Range-based interface for `getUpdates`
	 *
	 * This is a preferred way to receive updates because it lazily adjusts `offset` and calls `getUpdates`
	 * when necessary, allowing you to get more than a 100 updates in a single call.
	 * Params:
	 *     timeout         = Timeout in seconds for long polling
	 *     allowed_updates = List the types of updates you want your bot to receive
	 * Returns: An InputRange of `Update`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `getUpdates`
	 */
	auto pollUpdates(int timeout = 3, string[] allowed_updates = []) {
		struct pollUpdatesImpl {
		@safe:
			private {
				TelegramBot m_bot;
				Update[] m_buffer;
				size_t m_index;
				bool m_empty;

				int m_timeout;
				string[] m_allowed_updates;
			}

			this(TelegramBot bot, int timeout, string[] allowed_updates) {
				m_bot = bot;
				m_buffer.reserve = 100;

				m_timeout = timeout;
				m_allowed_updates = allowed_updates;
				this.popFront;
			}

			auto front() { return m_buffer[m_index]; }
			bool empty() { return m_empty; }
			void popFront() {
				if(m_buffer.length > ++m_index) {
					return;
				} else {
					m_buffer = m_bot.getUpdates(
						m_buffer.length ? m_buffer[$-1].update_id+1 : 0,
						100, // Limit
						m_timeout,
						m_allowed_updates,
					);
					m_index = 0;

					if(!m_buffer.length)
						m_empty = true;
				}
			}
		}


		return pollUpdatesImpl(this, timeout, allowed_updates);
	}

	@("pollUpdates() returns valid input range")
	unittest {
		import std.range : ElementType, isInputRange;
		import std.traits: ReturnType;
		static assert(isInputRange!(ReturnType!(TelegramBot.pollUpdates)) == true);
		static assert(is(ElementType!(ReturnType!(TelegramBot.pollUpdates)) == Update));
	}

	@("pollUpdates()")
	unittest {
		import std.range : generate, take, drop;
		import std.array : array;
		import std.algorithm : map;
		int requestNo;

		int updateNo;
		auto updates = generate!(() => Update(++updateNo)).take(400).array;

		auto fake = (string url, Json data) @trusted {
			url.should.be.equal("https://api.telegram.org/botTOKEN/getUpdates");

			auto j = Json([
					"limit": Json(100),
					"timeout": Json(3),
			]);

			if(requestNo)
				j["offset"] = Json((requestNo * 100) + 1);

			data.should.be.equal(j);

			if(requestNo++ > 3)
				return Json([
					"ok": Json(true),
					"result": Json.emptyArray,
				]);

			return Json([
				"ok": Json(true),
				"result": updates.drop((requestNo - 1) * 100).take(100).serializeToJson
			]);
		};

		TelegramBot("TOKEN", fake).pollUpdates()
			.map!(a => a.update_id).array.should.be.equal(updates.map!(a => a.update_id).array);
	}

	/**
	 * Set webhook to be used to receive incoming updates
	 *
	 * Params:
	 *     url          = HTTPS url to send updates to. Use an empty string to remove webhook integration
	 *     allowed_updates = List the types of updates you want your bot to receive
	 *     max_connections = Maximum allowed number of simultaneous HTTPS connections to the webhook for update delivery, 1-100
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * Deprecated: Webhooks aren't fully implemented,
	 * see an $(LINK2 https://gitlab.com/ohboi/tg.d/issues/4, issue) for more info
	 * See_Also: `SetWebhookMethod`, $(LINK https://core.telegram.org/bots/api#setwebhook)
	 */
	deprecated("Webhooks aren't fully implemented yet")
	bool setWebhook(string url, string[] allowed_updates = [], int max_connections = 40) {
		SetWebhookMethod m = {
			url: url,
			allowed_updates: allowed_updates,
			max_connections: max_connections,
		};

		return callMethod!bool(m);
	}

	/**
	 * Delete webhook integration
	 *
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * Deprecated: Webhooks aren't fully implemented,
	 * see an $(LINK2 https://gitlab.com/ohboi/tg.d/issues/4, issue) for more info
	 * See_Also: $(LINK https://core.telegram.org/bots/api#deletewebhook)
	 */
	deprecated("Webhooks aren't fully implemented yet")
	bool deleteWebhook() {
		return callMethod!bool(DeleteWebhookMethod());
	}

	/**
	 * Get current webhook status
	 *
	 * Throws: `TelegramBotException` on errors
	 * Deprecated: Webhooks aren't fully implemented,
	 * see an $(LINK2 https://gitlab.com/ohboi/tg.d/issues/4, issue) for more info
	 * See_Also: $(LINK https://core.telegram.org/bots/api#getwebhookinfo)
	 */
	deprecated("Webhooks aren't fully implemented yet")
	WebhookInfo getWebhookInfo() {
		return callMethod!WebhookInfo(GetWebhookInfoMethod());
	}

	/**
	 * Get current bot info
	 *
	 * Returns: Basic information about the bot in a `User` structure
	 * Throws: `TelegramBotException` on errors
	 * See_Also: $(LINK https://core.telegram.org/bots/api#getme)
	 */
	User getMe() {
		return callMethod!User(GetMeMethod());
	}

	@("getMe()")
	unittest {
		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/getMe");
				data.should.be.equal(Json.emptyObject);

				return Json([
					"ok": Json(true),
					"result": Json([
						"id": Json(42),
						"is_bot": Json(true),
						"first_name": Json("John"),
					])
				]);
			}
		).getMe.should.be.equal(
			User(42, true, "John")
		);

		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/getMe");
				data.should.be.equal(Json.emptyObject);

				return Json([
					"ok": Json(true),
					"result": Json([
						"id": Json(42),
						"is_bot": Json(false),
						"first_name": Json("John"),
						"last_name": Json("Smith"),
						"username": Json("js"),
						"language_code": Json("en-GB")
					])
				]);
			}
		).getMe.should.be.equal(
			User(42, false, "John", "Smith", "js", "en-GB")
		);
	}

	/**
	 * Send text message
	 *
	 * Params:
	 *     chat_id  = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     reply_to = If the message is a reply, ID of the original message
	 *     text     = Text to be sent
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendMessageMethod`, $(LINK https://core.telegram.org/bots/api#sendmessage)
	 */
	Message sendMessage(T)(T chat_id, string text) if(isTelegramID!T) {
		SendMessageMethod m = {
			text: text,
			chat_id: chat_id,
		};

		return sendMessage(m);
	}
	/// ditto
	Message sendMessage(T)(T chat_id, int reply_to, string text) if(isTelegramID!T) {
		SendMessageMethod m = {
			text: text,
			chat_id: chat_id,
			reply_to_message_id: reply_to,
		};

		return sendMessage(m);
	}
	/// ditto
	Message sendMessage(SendMessageMethod m) {
		return callMethod!Message(m);
	}

	@("sendMessage()")
	unittest {
		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/sendMessage");
				data.should.be.equal(
					Json([
						"chat_id": Json(42),
						"text": Json("text"),
					])
				);

				return Json([
					"ok": Json(true),
					"result": Message().serializeToJson,
				]);
			}
		).sendMessage(42L, "text").isNull.should.be.equal(true);

		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/sendMessage");
				data.should.be.equal(
					Json([
						"chat_id": Json("@superchat"),
						"text": Json("text"),
						"reply_to_message_id": Json(123),
					])
				);

				return Json([
					"ok": Json(true),
					"result": Message().serializeToJson,
				]);
			}
		).sendMessage("@superchat", 123, "text").isNull.should.be.equal(true);
	}

	/**
	 * Forward message from `from_chat_id` to `chat_id`
	 *
	 * Params:
	 *     chat_id      = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     from_chat_id = Unique identifier for the chat where the original message was sent (or channel username in the format `@channelusername`)
	 *     message_id   = ID of the original message
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `ForwardMessageMethod`, $(LINK https://core.telegram.org/bots/api#forwardmessage)
	 */
	Message forwardMessage(T1, T2)(T1 chat_id, T2 from_chat_id, int message_id)
	if(isTelegramID!T1 && isTelegramID!T2){
		ForwardMessageMethod m = {
			message_id: message_id,
			chat_id: chat_id,
			from_chat_id: from_chat_id,
		};

		return callMethod!Message(m);
	}
	/// ditto
	Message forwardMessage(ForwardMessageMethod m) {
		return callMethod!Message(m);
	}

	@("forwardMessage()")
	unittest {
		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/forwardMessage");
				data.should.be.equal(
					Json([
						"chat_id": Json(42),
						"from_chat_id": Json(43),
						"message_id": Json(1337),
					])
				);

				return Json([
					"ok": Json(true),
					"result": Message().serializeToJson,
				]);
			}
		).forwardMessage(42L, 43L, 1337).isNull.should.be.equal(true);
	}

	/**
	 * Send photo
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     photo   = HTTP URL to get photo from the internet or `file_id` of the file on Telegram
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendPhotoMethod`, $(LINK https://core.telegram.org/bots/api#sendphoto)
	 */
	Message sendPhoto(T)(T chat_id, string photo) if(isTelegramID!T) {
		SendPhotoMethod m = {
			photo: photo,
			chat_id: chat_id,
		};

		return sendPhoto(m);
	}
	/// ditto
	Message sendPhoto(SendPhotoMethod m) {
		return callMethod!Message(m);
	}

	@("sendPhoto()")
	unittest {
		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/sendPhoto");
				data.should.be.equal(
					Json([
						"chat_id": Json(42),
						"photo": Json("https://example.com/dogs.jpg"),
					]),
				);

				return Json([
					"ok": Json(true),
					"result": Message().serializeToJson,
				]);
			}
		).sendPhoto(42L, "https://example.com/dogs.jpg").isNull.should.be.equal(true);
	}

	/**
	 * Send audio
	 *
	 * Audio must be in mp3 format
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     audio   = HTTP URL to get audio from the internet or `file_id` of the file on Telegram
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendAudioMethod`, $(LINK https://core.telegram.org/bots/api#sendaudio)
	 */
	Message sendAudio(T)(T chat_id, string audio) if(isTelegramID!T) {
		SendAudioMethod m = {
			audio: audio,
			chat_id: chat_id,
		};

		return sendAudio(m);
	}
	/// ditto
	Message sendAudio(SendAudioMethod m) {
		return callMethod!Message(m);
	}

	@("sendAudio()")
	unittest {
		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/sendAudio");
				data.should.be.equal(
					Json([
						"chat_id": Json(42),
						"audio": Json("https://example.com/woof.mp3"),
					]),
				);

				return Json([
					"ok": Json(true),
					"result": Message().serializeToJson,
				]);
			}
		).sendAudio(42L, "https://example.com/woof.mp3").isNull.should.be.equal(true);
	}

	/**
	 * Send file
	 *
	 * Params:
	 *     chat_id  = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     document = HTTP URL to get document from the internet or `file_id` of the file on Telegram
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendDocumentMethod`, $(LINK https://core.telegram.org/bots/api#senddocument)
	 */
	Message sendDocument(T)(T chat_id, string document) if(isTelegramID!T) {
		SendDocumentMethod m = {
			document: document,
			chat_id: chat_id,
		};

		return sendDocument(m);
	}
	/// ditto
	Message sendDocument(SendDocumentMethod m) {
		return callMethod!Message(m);
	}

	@("sendDocument()")
	unittest {
		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/sendDocument");
				data.should.be.equal(
					Json([
						"chat_id": Json(42),
						"document": Json("https://example.com/document.pdf"),
					]),
				);

				return Json([
					"ok": Json(true),
					"result": Message().serializeToJson,
				]);
			}
		).sendDocument(42L, "https://example.com/document.pdf").isNull.should.be.equal(true);
	}

	/**
	 * Send video
	 *
	 * Video must be in mp4 format
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     video   = HTTP URL to get video from the internet or `file_id` of the file on Telegram
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendVideoMethod`, $(LINK https://core.telegram.org/bots/api#sendvideo)
	 */
	Message sendVideo(T)(T chat_id, string video) if(isTelegramID!T) {
		SendVideoMethod m = {
			video: video,
			chat_id: chat_id,
		};

		return sendVideo(m);
	}
	/// ditto
	Message sendVideo(SendVideoMethod m) {
		return callMethod!Message(m);
	}

	@("sendVideo()")
	unittest {
		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/sendVideo");
				data.should.be.equal(
					Json([
						"chat_id": Json(42),
						"video": Json("https://example.com/video.mp4"),
					]),
				);

				return Json([
					"ok": Json(true),
					"result": Message().serializeToJson,
				]);
			}
		).sendVideo(42L, "https://example.com/video.mp4").isNull.should.be.equal(true);
	}

	/**
	 * Send animation
	 *
	 * Animation must be in GIF format or H.264/MPEG-4 AVC video without sound 
	 *
	 * Params:
	 *     chat_id   = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     animation = HTTP URL to get animation from the internet or `file_id` of the file on Telegram
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendAnimationMethod`, $(LINK https://core.telegram.org/bots/api#sendanimation)
	 */
	Message sendAnimation(T)(T chat_id, string animation) if(isTelegramID!T) {
		SendAnimationMethod m = {
			animation: animation,
			chat_id: chat_id,
		};

		return sendAnimation(m);
	}
	/// ditto
	Message sendAnimation(SendAnimationMethod m) {
		return callMethod!Message(m);
	}

	@("sendAnimation()")
	unittest {
		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/sendAnimation");
				data.should.be.equal(
					Json([
						"chat_id": Json(42),
						"animation": Json("https://example.com/me.gif"),
					]),
				);

				return Json([
					"ok": Json(true),
					"result": Message().serializeToJson,
				]);
			}
		).sendAnimation(42L, "https://example.com/me.gif").isNull.should.be.equal(true);
	}

	/**
	 * Send voice message
	 *
	 * Voice message must be in ogg format encoded with OPUS
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     voice   = HTTP URL to get audio from the internet or `file_id` of the file on Telegram
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendVoiceMethod`, $(LINK https://core.telegram.org/bots/api#sendvoice)
	 */
	Message sendVoice(T)(T chat_id, string voice) if(isTelegramID!T) {
		SendVoiceMethod m = {
			voice: voice,
			chat_id: chat_id,
		};

		return sendVoice(m);
	}
	/// ditto
	Message sendVoice(SendVoiceMethod m) {
		return callMethod!Message(m);
	}

	@("sendVoice()")
	unittest {
		TelegramBot(
			"TOKEN",
			(string url, Json data) @trusted {
				url.should.be.equal("https://api.telegram.org/botTOKEN/sendVoice");
				data.should.be.equal(
					Json([
						"chat_id": Json(42),
						"voice": Json("https://example.com/voice.ogg"),
					]),
				);

				return Json([
					"ok": Json(true),
					"result": Message().serializeToJson,
				]);
			}
		).sendVoice(42L, "https://example.com/voice.ogg").isNull.should.be.equal(true);
	}

	/**
	 * Send video message
	 *
	 * Video must be square and shoudln't be longer than 1 minute
	 *
	 * Params:
	 *     chat_id    = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     video_note = HTTP URL to get video from the internet or `file_id` of the file on Telegram
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendVideoNoteMethod`, $(LINK https://core.telegram.org/bots/api#sendvideonote)
	 */
	Message sendVideoNote(T)(T chat_id, string video_note) if(isTelegramID!T) {
		SendVideoNoteMethod m = {
			video_note: video_note,
			chat_id: chat_id,
		};

		return sendVideoNote(m);
	}
	/// ditto
	Message sendVideoNote(SendVideoNoteMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Send group of photos or videos as an album
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     media   = Photos and videos to be sent
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendMediaGroupMethod`, $(LINK https://core.telegram.org/bots/api#sendmediagroup)
	 */
	Message sendMediaGroup(T)(T chat_id, Algebraic!(InputMediaPhoto, InputMediaVideo)[] media)
	if(isTelegramID!T)
	in(2 <= media.length && media.length <= 10) {
		SendMediaGroupMethod m = {
			media: media,
			chat_id: chat_id,
		};

		return sendMediaGroup(m);
	}
	/// ditto
	Message sendMediaGroup(SendMediaGroupMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Send point on the map
	 *
	 * Params:
	 *     chat_id   = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     latitude  = Latitude of the location
	 *     longitude = Longitude of the location
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendLocationMethod`, $(LINK https://core.telegram.org/bots/api#sendlocation)
	 */
	Message sendLocation(T)(T chat_id, float latitude, float longitude) if(isTelegramID!T) {
		SendLocationMethod m = {
			latitude: latitude,
			longitude: longitude,
			chat_id: chat_id,
		};

		return sendLocation(m);
	}
	/// ditto
	Message sendLocation(SendLocationMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Edit live location message
	 *
	 * Overloads take either `chat_id` and `message_id` or `inline_message_id`
	 *
	 * Params:
	 *     chat_id           = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     message_id        = ID of the message to edit
	 *     inline_message_id = ID of the inline message
	 *     latitude          = Latitude of new location
	 *     longitude         = longitude of new location
	 * Returns: Edited `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `EditMessageLiveLocationMethod`, $(LINK https://core.telegram.org/bots/api#editmessagelivelocation)
	 */
	 Message editMessageLiveLocation(T)(T chat_id, int message_id, float latitude, float longitude)
	if(isTelegramID!T) {
		EditMessageLiveLocationMethod m = {
			message_id: message_id,
			latitude: latitude,
			longitude: longitude,
			chat_id: chat_id,
		};

		return editMessageLiveLocation(m);
	}
	/// ditto
	Message editMessageLiveLocation(string inline_message_id, float latitude, float longitude) {
		EditMessageLiveLocationMethod m = {
			inline_message_id: inline_message_id,
			latitude : latitude,
			longitude : longitude,
		};

		return editMessageLiveLocation(m);
	}
	/// ditto
	Message editMessageLiveLocation(EditMessageLiveLocationMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Stop updating a live location message
	 *
	 * Overloads take either `chat_id` and `message_id` or `inline_message_id`
	 *
	 * Params:
	 *     chat_id           = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     message_id        = ID of the message to edit
	 *     inline_message_id = ID of the inline message
	 * Returns: Edited `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `StopMessageLiveLocation`, $(LINK https://core.telegram.org/bots/api#stopmessagelivelocation)
	 */
	Message stopMessageLiveLocation(T)(T chat_id, int message_id) if(isTelegramID!T) {
		StopMessageLiveLocationMethod m = {
			message_id: message_id,
			chat_id: chat_id,
		};

		return stopMessageLiveLocation(m);
	}
	/// ditto
	Message stopMessageLiveLocation(string inline_message_id) {
		StopMessageLiveLocationMethod m = {
			inline_message_id: inline_message_id,
		};

		return stopMessageLiveLocation(m);
	}
	/// ditto
	Message stopMessageLiveLocation(StopMessageLiveLocationMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Send information about a venue
	 *
	 * Params:
	 *     chat_id   = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     latitude  = Latitude of the venue
	 *     longitude = Longitude of the venue
	 *     title     = Name of the venue
	 *     address   = Address of the venue
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendVenueMethod`, $(LINK https://core.telegram.org/bots/api#sendvenue)
	 */
	Message sendVenue(T)(T chat_id, float latitude, float longitude, string title, string address)
	if(isTelegramID!T) {
		SendVenueMethod m = {
			latitude: latitude,
			longitude : longitude,
			title : title,
			address : address,
			chat_id: chat_id,
		};

		return sendVenue(m);
	}
	/// ditto
	Message sendVenue(SendVenueMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Send phone contact
	 *
	 * Params:
	 *     chat_id      = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     phone_number = Contact's phone number
	 *     first_name   = Contact's first name
	 *     last_name    = Contact's last name
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendContactMethod`, $(LINK https://core.telegram.org/bots/api#sendcontact)
	 */
	Message sendContact(T)(T chat_id, string phone_number, string first_name, string last_name = "")
	if(isTelegramID!T) {
		SendContactMethod m = {
			phone_number: phone_number,
			first_name : first_name,
			last_name: last_name,
			chat_id: chat_id,
		};

		return sendContact(m);
	}
	/// ditto
	Message sendContact(SendContactMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Send chat action
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel  (in the format `@channelusername`)
	 *     action  = Type of action, (typing, upload_photo, record_video, etc)
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendChatActionMethod`, $(LINK https://core.telegram.org/bots/api#sendchataction)
	 */
	bool sendChatAction(T)(T chat_id, string action) if(isTelegramID!T) {
		SendChatActionMethod m = {
			action: action,
			chat_id: chat_id,
		};

		return sendChatAction(m);
	}
	/// ditto
	bool sendChatAction(SendChatActionMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Get a list of profile pictures for specified user
	 *
	 * Params:
	 *     user_id = Unique identifier of the target user
	 * Returns: `UserProfilePhotos` struct
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `GetUserProfilePhotosMethod`, $(LINK https://core.telegram.org/bots/api#getuserprofilephotos)
	 */
	UserProfilePhotos getUserProfilePhotos(int user_id) {
		GetUserProfilePhotosMethod m = {
			user_id: user_id,
		};

		return getUserProfilePhotos(m);
	}
	/// ditto
	UserProfilePhotos getUserProfilePhotos(GetUserProfilePhotosMethod m) {
		return callMethod!UserProfilePhotos(m);
	}

	/**
	 * Get info about a file and prepare it for downloading
	 *
	 * Params:
	 *     file_id      = File identifier to get info about
	 * Returns: `File` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `GetFileMethod`, $(LINK https://core.telegram.org/bots/api#getfile)
	 */
	File getFile(string file_id) {
		GetFileMethod m = {
			file_id: file_id,
		};

		return getFile(m);
	}
	/// ditto
	File getFile(GetFileMethod m) {
		return callMethod!File(m);
	}

	/**
	 * Kick a user from a group, a supergroup or a channel
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target group or username of the target supergroup or channel (in the format `@channelusername`)
	 *     user_id = Unique identifier of the target user
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `KickChatMemberMethod`, $(LINK https://core.telegram.org/bots/api#kickchatmember)
	 */
	bool kickChatMember(T)(T chat_id, int user_id) if(isTelegramID!T) {
		KickChatMemberMethod m = {
			user_id: user_id,
			chat_id: chat_id,
		};

		return kickChatMember(m);
	}
	/// ditto
	bool kickChatMember(KickChatMemberMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Unban a previously kicked user in a group, a supergroup or a channel
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target group or username of the target supergroup or channel (in the format `@username`)
	 *     user_id = Unique identifier of the target user
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `UnbanChatMemberMethod`, $(LINK https://core.telegram.org/bots/api#unbanchatmember)
	 */
	bool unbanChatMember(T)(T chat_id, int user_id) if(isTelegramID!T) {
		UnbanChatMemberMethod m = {
			user_id: user_id,
			chat_id: chat_id,
		};

		return unbanChatMember(m);
	}
	/// ditto
	bool unbanChatMember(UnbanChatMemberMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Restrict a user in a supergroup
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target supergroup (in the format `@supergroupusername`)
	 *     user_id = Unique identifier of the target user
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `RestrictChatMemberMethod`, $(LINK https://core.telegram.org/bots/api#restrictchatmember)
	 */
	bool restrictChatMember(T)(T chat_id, int user_id) if(isTelegramID!T) {
		RestrictChatMemberMethod m = {
			user_id: user_id,
			chat_id: chat_id,
		};

		return restrictChatMember(m);
	}
	/// ditto
	bool restrictChatMember(RestrictChatMemberMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Promote or demote a user in a supergroup or a channel
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     user_id = Unique identifier of the target user
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `PromoteChatMemberMethod`, $(LINKhttps://core.telegram.org/bots/api#promotechatmember)
	 */
	bool promoteChatMember(T)(T chat_id, int user_id) if(isTelegramID!T) {
		PromoteChatMemberMethod m = {
			user_id: user_id,
			chat_id: chat_id,
		};

		return promoteChatMember(m);
	}
	/// ditto
	bool promoteChatMember(PromoteChatMemberMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Generate a new invite link for a chat
	 *
	 * Any previously generated link is revoked
	 *
	 * Params:
	 *     chat_id      = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 * Returns: invite link
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `ExportChatInviteLinkMethod`, $(LINK https://core.telegram.org/bots/api#exportchatinvitelink)
	 */
	string exportChatInviteLink(T)(T chat_id) if(isTelegramID!T) {
		ExportChatInviteLinkMethod m = {
			chat_id: chat_id,
		};

		return exportChatInviteLink(m);
	}
	/// ditto
	string exportChatInviteLink(ExportChatInviteLinkMethod m) {
		return callMethod!string(m);
	}

	/**
	 * Set a new profile photo for the chat
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     photo   = New chat photo
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * Deprecated: `InputFile` isn't supported yet
	 * See_Also: `SetChatPhotoMethod`, $(LINK https://core.telegram.org/bots/api#setchatphoto)
	 */
	deprecated("InputFile and every method that uses it aren't supported yet")
	bool setChatPhoto(T)(T chat_id, InputFile photo) if(isTelegramID!T) {
		SetChatPhotoMethod m = {
			photo: photo,
			chat_id: chat_id,
		};

		return setChatPhoto(m);
	}
	/// ditto
	bool setChatPhoto(SetChatPhotoMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Delete a chat photo
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `deleteChatPhoto`, $(LINK https://core.telegram.org/bots/api#deletechatphoto)
	 */
	bool deleteChatPhoto(T)(T chat_id) if(isTelegramID!T) {
		DeleteChatPhotoMethod m = {
			chat_id: chat_id,
		};

		return deleteChatPhoto(m);
	}
	/// ditto
	bool deleteChatPhoto(DeleteChatPhotoMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Change the title of a chat
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     title   = New chat title
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SetChatTitleMethod`, $(LINK https://core.telegram.org/bots/api#setchattitle)
	 */
	bool setChatTitle(T)(T chat_id, string title)
	if(isTelegramID!T)
	in(1 <= title.length && title.length <= 255) {
		SetChatTitleMethod m = {
			title: title,
			chat_id: chat_id,
		};

		return setChatTitle(m);
	}
	/// title
	bool setChatTitle(SetChatTitleMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Change the description of a supergroup or a channel
	 *
	 * Params:
	 *     chat_id     = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     description = New chat description
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SetChatDescriptionMethod`, $(LINK https://core.telegram.org/bots/api#setchatdescription)
	 */
	bool setChatDescription(T)(T chat_id, string description = "")
	if(isTelegramID!T)
	in(title.length <= 255) {
		SetChatDescriptionMethod m = {
			description: description,
			chat_id: chat_id,
		};

		return setChatDescription(m);
	}
	/// ditto
	bool setChatDescription(SetChatDescriptionMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Pin a message in a supergroup or a channel
	 *
	 * Params:
	 *     chat_id    = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     message_id = Identifier of a message to pin
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `PinChatMessageMethod`, $(LINK https://core.telegram.org/bots/api#pinchatmessage)
	 */
	bool pinChatMessage(T)(T chat_id, int message_id) if(isTelegramID!T) {
		PinChatMessageMethod m = {
			message_id: message_id,
			chat_id: chat_id,
		};

		return pinChatMessage(m);
	}
	/// ditto
	bool pinChatMessage(PinChatMessageMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Unpin a message in a supergroup or a channel
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `UnpinChatMessageMethod`, $(LINK https://core.telegram.org/bots/api#unpinchatmessage)
	 */
	bool unpinChatMessage(T)(T chat_id) if(isTelegramID!T) {
		UnpinChatMessageMethod m = {
			chat_id: chat_id,
		};

		return unpinChatMessage(m);
	}
	/// ditto
	bool unpinChatMessage(UnpinChatMessageMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Leave a group, supergroup or channel
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `LeaveChatMethod`, $(LINK https://core.telegram.org/bots/api#leavechat)
	 */
	bool leaveChat(T)(T chat_id) if(isTelegramID!T) {
		LeaveChatMethod m = {
			chat_id: chat_id,
		};

		return leaveChat(m);
	}
	/// ditto
	bool leaveChat(LeaveChatMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Get up-to-date information about the chat
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 * Returns: `Chat` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `GetChatMethod`, $(LINK https://core.telegram.org/bots/api#getchat)
	 */
	Chat getChat(T)(T chat_id) if(isTelegramID!T) {
		GetChatMethod m = {
			chat_id: chat_id,
		};

		return getChat(m);
	}
	/// ditto
	Chat getChat(GetChatMethod m) {
		return callMethod!Chat(m);
	}

	/**
	 * Get a list of administrators in a chat
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target supergroup or channel (in the format `@channelusername`)
	 * Returns: An array of `ChatMember` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `GetChatAdministatorsMethod`, $(LINK https://core.telegram.org/bots/api#getchatadministrators)
	 */
	ChatMember[] getChatAdministrators(T)(T chat_id) if(isTelegramID!T) {
		GetChatAdministratorsMethod m = {
			chat_id: chat_id,
		};

		return getChatAdministrators(m);
	}
	/// ditto
	ChatMember[] getChatAdministrators(GetChatAdministratorsMethod m) {
		return callMethod!(ChatMember[])(m);
	}

	/**
	 * Get the number of members in a chat
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target supergroup or channel (in the format `@channelusername`)
	 * Returns: number of members
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `GetChatMembersCountMethod`, $(LINK https://core.telegram.org/bots/api#getchatmemberscount)
	 */
	int getChatMembersCount(T)(T chat_id) if(isTelegramID!T) {
		GetChatMembersCountMethod m = {
			chat_id: chat_id,
		};

		return getChatMembersCount(m);
	}
	/// ditto
	int getChatMembersCount(GetChatMembersCountMethod m) {
		return callMethod!int(m);
	}

	/**
	 * Get information about a member of a chat
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target supergroup or channel (in the format `@channelusername`)
	 *     user_id = Unique identifier of the target user
	 * Returns: `ChatMember` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `GetChatMemberMethod`, $(LINK https://core.telegram.org/bots/api#getchatmember)
	 */
	ChatMember getChatMember(T)(T chat_id, int user_id) if(isTelegramID!T) {
		GetChatMemberMethod m = {
			user_id: user_id,
			chat_id: chat_id,
		};

		return getChatMember(m);
	}
	/// ditto
	ChatMember getChatMember(GetChatMemberMethod m) {
		return callMethod!ChatMember(m);
	}

	/**
	 * Set a new group sticker set for a supergroup
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target supergroup (in the format `@supergroupusername`)
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SetCharStickerMethod`, $(LINK https://core.telegram.org/bots/api#setchatstickerset)
	 */
	bool setChatStickerSet(T)(T chat_id, string sticker_set_name) if(isTelegramID!T) {
		SetChatStickerSetMethod m = {
			sticker_set_name: sticker_set_name,
			chat_id: chat_id,
		};

		return setChatStickerSet(m);
	}
	/// ditto
	bool setChatStickerSet(SetChatStickerSetMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Delete a group sticker set from a supergroup
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target supergroup (in the format `@supergroupusername`)
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `DeleteChatStickerSet`, $(LINK https://core.telegram.org/bots/api#deletechatstickerset)
	 */
	bool deleteChatStickerSet(T)(T chat_id) if(isTelegramID!T) {
		DeleteChatStickerSetMethod m = {
			chat_id: chat_id,
		};

		return deleteChatStickerSet(m);
	}
	/// ditto
	bool deleteChatStickerSet(DeleteChatStickerSetMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Answer to a callback query sent from inline keyboard
	 *
	 * Params:
	 *     callback_query_id = Unique identifier for the query to be answered
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `AnswerCallbackQueryMethod`, $(LINK https://core.telegram.org/bots/api#answercallbackquery)
	 */
	bool answerCallbackQuery(string callback_query_id) {
		AnswerCallbackQueryMethod m = {
			callback_query_id: callback_query_id,
		};

		return answerCallbackQuery(m);
	}
	/// ditto
	bool answerCallbackQuery(AnswerCallbackQueryMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Edit text of a message
	 *
	 * Overloads take either `chat_id` and `message_id` or `inline_message_id`
	 *
	 * Params:
	 *     chat_id           = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     message_id        = Identifier of the sent message
	 *     inline_message_id = Identifier of the inline message
	 *     text              = New text of the message
	 * Returns: Edited `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `EditMessageTextMethod`, $(LINK https://core.telegram.org/bots/api#editmessagetext)
	 */
	Message editMessageText(T)(T chat_id, int message_id, string text)
	if(isTelegramID!T) {
		EditMessageTextMethod m = {
			message_id: message_id,
			text: text,
			chat_id: chat_id,
		};

		return editMessageText(m);
	}
	/// ditto
	Message editMessageText(string inline_message_id, string text) {
		EditMessageTextMethod m = {
			inline_message_id: inline_message_id,
			text: text,
		};

		return editMessageText(m);
	}
	/// ditto
	Message editMessageText(EditMessageTextMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Edit caption of a message
	 *
	 * Overloads take either `chat_id` and `message_id` or `inline_message_id`
	 *
	 * Params:
	 *     chat_id           = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     message_id        = Identifier of the sent message
	 *     inline_message_id = Identifier of the inline message
	 *     caption           = New caption of the message
	 * Returns: Edited `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `EditMessageCaptionMethod`, $(LINK https://core.telegram.org/bots/api#editmessagecaption)
	 */
	Message editMessageCaption(T)(T chat_id, int message_id, string caption)
	if(isTelegramID!T) {
		EditMessageCaptionMethod m = {
			message_id: message_id,
			caption: caption,
			chat_id: chat_id,
		};

		return editMessageCaption(m);
	}
	/// ditto
	Message editMessageCaption(string inline_message_id, string caption) {
		EditMessageCaptionMethod m = {
			inline_message_id: inline_message_id,
			caption: caption,
		};

		return editMessageCaption(m);
	}
	/// ditto
	Message editMessageCaption(EditMessageCaptionMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Edit audio, document, photo or video message
	 *
	 * Overloads take either `chat_id` and `message_id` or `inline_message_id`
	 *
	 * Params:
	 *     chat_id           = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     message_id        = Identifier of the sent message
	 *     inline_message_id = Identifier of the inline message
	 *     media             = New media content of the message
	 * Returns: Edited `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `EditMessageMediaMethod`, $(LINK https://core.telegram.org/bots/api#editmessagemedia)
	 */
	Message editMessageMedia(T)(T chat_id, int message_id, InputMedia media) {
		EditMessageMediaMethod m = {
			chat_id: chat_id,
			message_id: message_id,
			media: media,
		};
		return editMessageMedia(m);
	}
	/// ditto
	Message editMessageMedia(string inline_message_id, InputMedia media) {
		EditMessageMediaMethod m = {
			inline_message_id: inline_message_id,
			media: media,
		};
		return editMessageMedia(m);
	}
	/// ditto
	Message editMessageMedia(EditMessageMediaMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Edit reply markup of a message
	 *
	 * Overloads take either `chat_id` and `message_id` or `inline_message_id`
	 *
	 * Params:
	 *     chat_id           = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     message_id        = Identifier of the sent message
	 *     inline_message_id = Identifier of the inline message
	 *     reply_markup      = Object for a new inline keyboard
	 * Returns: Edited `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `EditMessageReplyMarkup`, $(LINK https://core.telegram.org/bots/api#editmessagereplymarkup)
	 */
	Message editMessageReplyMarkup(T)(T chat_id, int message_id, InlineKeyboardMarkup reply_markup)
	if(isTelegramID!T) {
		EditMessageReplyMarkupMethod m = {
			message_id: message_id,
			chat_id: chat_id,
			reply_markup: reply_markup,
		};

		return editMessageReplyMarkup(m);
	}
	/// ditto
	Message editMessageReplyMarkup(string inline_message_id, InlineKeyboardMarkup reply_markup) {
		EditMessageReplyMarkupMethod m = {
			inline_message_id: inline_message_id,
			reply_markup: reply_markup,
		};

		return editMessageReplyMarkup(m);
	}
	/// ditto
	Message editMessageReplyMarkup(EditMessageReplyMarkupMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Delete a message
	 *
	 * Params:
	 *     chat_id    = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     message_id = Identifier of the message to delete
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `DeleteMessageMethod`, $(LINK https://core.telegram.org/bots/api#deletemessage)
	 */
	bool deleteMessage(T)(T chat_id, int message_id) if(isTelegramID!T) {
		DeleteMessageMethod m = {
			message_id: message_id,
			chat_id: chat_id,
		};

		return deleteMessage(m);
	}
	/// ditto
	bool deleteMessage(DeleteMessageMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Send webp sticker
	 *
	 * Params:
	 *     chat_id = Unique identifier for the target chat or username of the target channel (in the format `@channelusername`)
	 *     sticker = HTTP URL to get sticker from the internet or `file_id` of the file on Telegram
	 * Returns: Sent `Message`
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SendStickerMethod`, $(LINK https://core.telegram.org/bots/api#sendsticker)
	 */
	Message sendSticker(T)(T chat_id, string sticker) if(isTelegramID!T) {
		SendStickerMethod m = {
			sticker: sticker,
			chat_id: chat_id,
		};

		return sendSticker(m);
	}
	/// ditto
	Message sendSticker(SendStickerMethod m) {
		return callMethod!Message(m);
	}

	/**
	 * Get a sticker set
	 *
	 * Params:
	 *     name = Name of the sticker set
	 * Returns: `StickerSet` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `GetStickerMethod`, $(LINK https://core.telegram.org/bots/api#getstickerset)
	 */
	StickerSet getStickerSet(string name) {
		GetStickerSetMethod m = {
			name: name,
		};

		return getStickerSet(m);
	}
	/// ditto
	StickerSet getStickerSet(GetStickerSetMethod m) {
		return callMethod!StickerSet(m);
	}

	/**
	 * Upload a .png file to create a new sticker set or add to an existing one
	 *
	 * Params:
	 *     user_id     = User identifier of sticker file owner
	 *     png_sticker = Png image with the sticker
	 * Returns: Uploaded `File` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `UploadStickerFileMethod`, $(LINK https://core.telegram.org/bots/api#uploadstickerfile)
	 * Deprecated: `InputFile` isn't supported yet
	 */
	deprecated("InputFile and every method that uses it aren't supported yet")
	File uploadStickerFile(int user_id, InputFile png_sticker) {
		UploadStickerFileMethod m = {
			user_id: user_id,
			png_sticker: png_sticker,
		};

		return uploadStickerFile(m);
	}
	/// ditto
	File uploadStickerFile(UploadStickerFileMethod m) {
		return callMethod!File(m);
	}

	/**
	 * Create new sticker set owned by a user
	 *
	 * Params:
	 *     user_id     = User identifier of created sticker set owner
	 *     name        = Short name of sticker set, to be used in `t.me/addstickers/` URLs
	 *     title       = Sticker set title
	 *     png_sticker = Png image with a sticker, Pass `file_id` or an HTTP URL to get a file from the Internet
	 *     emojis      = One or more emoji corresponding to the sticker
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `CreateNewStickerSetMethod`, $(LINK https://core.telegram.org/bots/api#createnewstickerset)
	 */
	bool createNewStickerSet(int user_id,
		string name,
		string title,
		string png_sticker,
		string emojis) {
			CreateNewStickerSetMethod m = {
				user_id: user_id,
				name: name,
				title: title,
				png_sticker: png_sticker,
				emojis: emojis,
			};

			return createNewStickerSet(m);
	}
	/// ditto
	bool createNewStickerSet(CreateNewStickerSetMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Add a new sticker to a set
	 *
	 * Params:
	 *     user_id     = User identifier of created sticker set owner
	 *     name        = Sticker set name
	 *     png_sticker = Png image with a sticker, Pass `file_id` or an HTTP URL to get a file from the Internet
	 *     emojis      = One or more emoji corresponding to the sticker
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `AddStickerToSetMethod`, $(LINK https://core.telegram.org/bots/api#addstickertoset)
	 */
	bool addStickerToSet(int user_id, string name, string pngSticker, string emojis) {
		AddStickerToSetMethod m = {
			user_id: user_id,
			name : name,
			png_sticker: pngSticker,
			emojis: emojis,
		};

		return addStickerToSet(m);
	}
	/// ditto
	bool addStickerToSet(AddStickerToSetMethod m) {
		return callMethod!bool(m);
	}

	/**
	 * Move a sticker in a set to a specific position
	 *
	 * Params:
	 *     sticker  = File identifier of the sticker
	 *     position = New sticker position in the set, zero-based
	 * Returns: `true` on success
	 * Throws: `TelegramBotException` on errors
	 * See_Also: `SetStickerPositionInSetMethod`, $(LINK https://core.telegram.org/bots/api#setstickerpositioninset)
	 */
	bool setStickerPositionInSet(string sticker, int position) {
		SetStickerPositionInSetMethod m = {
			sticker: sticker,
			position: position,
		};

		return setStickerPositionInSet(m);
	}
	/// ditto
	bool setStickerPositionInSet(SetStickerPositionInSetMethod m) {
		return callMethod!bool(m);
	}

	bool deleteStickerFromSet(string sticker) {
		SetStickerPositionInSetMethod m = {
			sticker: sticker,
		};

		return setStickerPositionInSet(m);
	}

	bool deleteStickerFromSet(DeleteStickerFromSetMethod m) {
		return callMethod!bool(m);
	}

	bool answerInlineQuery(string inlineQueryId, InlineQueryResult[] results) {
		AnswerInlineQueryMethod m = {
			inline_query_id: inlineQueryId,
			results: results,
		};

		return answerInlineQuery(m);
	}

	bool answerInlineQuery(AnswerInlineQueryMethod m) {
		return callMethod!bool(m);
	}
}

/*                    Telegram types and enums                    */

enum ChatType : string {
	private_   = "private",
	group      = "group",
	supergroup = "supergroup",
	channel    = "channel"
}

enum ParseMode : string {
	none     = "",
	markdown = "Markdown",
	html     = "HTML",
}

struct InputFile {}

struct Update {
	int update_id;

@optional:
	Message message,
			edited_message,
			channel_post,
			edited_channel_post;
	InlineQuery inline_query;
	ChosenInlineResult chosen_inline_result;
	CallbackQuery callback_query;
	ShippingQuery shipping_query;
	PreCheckoutQuery pre_checkout_query;

@ignore @property:
	bool isNull() { return update_id == typeof(update_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct User {
	int id;
	bool is_bot;
	string first_name;

@optional:
	string last_name,
			username,
			language_code;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct Chat {
@safe:
	long id;
	ChatType type;

@optional:

	string title,
			username,
			first_name,
			last_name;
	bool all_members_are_administrators;
	ChatPhoto photo;
	string description,
			invite_link;

	private @name("pinned_message") Json m_pinned_message;
	@property @ignore {
		// Message pinned_message() {
		// 	return m_pinned_message.type == Json.Type.null_ 
		// 			? Message.init
		// 			: m_pinned_message.deserializeJson!Message;
		// }
		// void pinned_message(Message m) {
		// 	m_pinned_message = m.serializeToJson;
		// }
	}

	string sticker_set_name;
	bool can_set_sticker_set;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct Message {
@safe:
	int message_id;

	@property @ignore {
		int  id()      { return message_id; }
		void id(int i) { message_id = i;    }
	}

	long date;
	Chat chat;

@optional:
	User from;
	User forward_from;
	Chat forward_from_chat;
	int forward_from_message_id;
	string forward_signature;
	long forward_date;

	private @name("reply_to_message") Json m_reply_to_message;
	@property @ignore {
		// Message reply_to_message() {
		// 	return m_reply_to_message.type == Json.Type.null_ 
		// 			? Message.init
		// 			: m_reply_to_message.deserializeJson!Message;
		// }
		// void reply_to_message(Message m) {
		// 	m_reply_to_message = m.serializeToJson;
		// }
	}

	long edit_date;
	string media_group_id,
			author_signature,
			text;
	MessageEntity[] entities;
	MessageEntity[] caption_entities;
	Audio audio;
	Animation animation;
	Document document;
	Game game;
	PhotoSize[] photo;
	Sticker sticker;
	Video video;
	Voice voice;
	VideoNote video_note;
	string caption;
	Contact contact;
	Location location;
	Venue venue;
	User[] new_chat_members;
	User left_chat_member;
	string new_chat_title;
	PhotoSize[] new_chat_photo;
	bool delete_chat_photo,
			group_chat_created,
			supergroup_chat_created,
			channel_chat_created;
	long migrate_to_chat_id,
			migrate_from_chat_id;

	private @name("pinned_message") Json m_pinned_message;
	@property @ignore {
		// Message pinned_message() {
		// 	return m_pinned_message.type == Json.Type.null_ 
		// 			? Message.init
		// 			: m_pinned_message.deserializeJson!Message;
		// }
		// void pinned_message(Message m) {
		// 	m_pinned_message = m.serializeToJson;
		// }
	}

	Invoice invoice;
	SuccessfulPayment successful_payment;
	string connected_website;

@ignore @property:
	bool isNull() { return message_id == typeof(message_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct MessageEntity {
	string type;
	int offset;
	int length;

@optional:
	string url;
	User user;

@ignore @property:
	bool isNull() { return length == typeof(length).init; }
	deprecated typeof(this) get() { return this; }
}

struct PhotoSize {
	string file_id;
	int width;
	int height;

@optional:
	int file_size;

@ignore @property:
	bool isNull() { return file_id == typeof(file_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct Audio {
	string file_id;
	int duration;

@optional:
	string performer,
			title,
			mime_type;
	int file_size;
	PhotoSize thumb;

@ignore @property:
	bool isNull() { return file_id == typeof(file_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct Document {
	string file_id;

@optional:
	PhotoSize thumb;
	string file_name,
			mime_type;
	int file_size;

@ignore @property:
	bool isNull() { return file_id == typeof(file_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct Video {
	string file_id;
	int width,
		height,
		duration;

@optional:
	PhotoSize thumb;
	string mime_type;
	int file_size;

@ignore @property:
	bool isNull() { return file_id == typeof(file_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct Voice {
	string file_id;
	int duration;

@optional:
	string mime_type;
	int file_size;

@ignore @property:
	bool isNull() { return file_id == typeof(file_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct VideoNote {
	string file_id;
	int length,
		duration;

@optional:
	PhotoSize thumb;
	int file_size;

@ignore @property:
	bool isNull() { return file_id == typeof(file_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct Contact {
	string phone_number,
		   first_name;

@optional:
	string last_name;
	int user_id;
	string vcard;

@ignore @property:
	bool isNull() { return phone_number == typeof(phone_number).init; }
	deprecated typeof(this) get() { return this; }
}

struct Location {
	float longitude,
		  latitude;

@ignore @property:
	bool isNull() { return longitude.isNaN; }
	deprecated typeof(this) get() { return this; }
}

struct Venue {
	Location location;
	string title,
		   address;

@optional:
	string foursquare_id;
	string foursquare_type;

@ignore @property:
	bool isNull() { return location.isNull; }
	deprecated typeof(this) get() { return this; }
}

struct UserProfilePhotos {
	int total_count;
	PhotoSize[] photos;

@ignore @property:
	bool isNull() { return total_count == typeof(total_count).init; }
	deprecated typeof(this) get() { return this; }
}

struct File {
	string file_id;

@optional:
	int file_size;
	string file_path;

@ignore @property:
	bool isNull() { return file_id == typeof(file_id).init; }
	deprecated typeof(this) get() { return this; }
}

private alias ReplyMarkupStructs = AliasSeq!(ReplyKeyboardMarkup, ReplyKeyboardRemove,
		InlineKeyboardMarkup, ForceReply);

/**
 Abstract structure for unioining ReplyKeyboardMarkup, ReplyKeyboardRemove,
 InlineKeyboardMarkup and ForceReply
*/
alias ReplyMarkup = Algebraic!ReplyMarkupStructs;
enum isReplyMarkup(T) = is(T == ReplyMarkup) || staticIndexOf!(T, ReplyMarkupStructs) >= 0;

struct ReplyKeyboardMarkup {
	KeyboardButton[][] keyboard;

@optional:
	bool resize_keyboard,
			one_time_keyboard,
			selective;

@ignore @property:
	bool isNull() { return keyboard == typeof(keyboard).init; }
	deprecated typeof(this) get() { return this; }
}

struct KeyboardButton {
	string text;

@optional:
	bool request_contact,
			request_location;

@ignore @property:
	bool isNull() { return text == typeof(text).init; }
	deprecated typeof(this) get() { return this; }
}

struct ReplyKeyboardRemove {
	bool remove_keyboard;

@optional:
	bool selective;

@ignore @property:
	bool isNull() { return remove_keyboard == typeof(remove_keyboard).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineKeyboardMarkup {
	InlineKeyboardButton[][] inline_keyboard;

@ignore @property:
	bool isNull() { return inline_keyboard == typeof(inline_keyboard).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineKeyboardButton {
	string text;

@optional:
	string url,
		   callback_data,
		   switch_inline_query,
		   switch_inline_query_current_chat;
	CallbackGame callback_game;
	bool pay;

@ignore @property:
	bool isNull() { return text == typeof(text).init; }
	deprecated typeof(this) get() { return this; }
}

struct CallbackQuery {
	string id;
	User from;
	string chat_instance;

@optional:
	Message message;
	string inline_message_id,
			data,
			game_short_name;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct ForceReply {
	bool force_reply;

@optional:
	bool selective;

@ignore @property:
	bool isNull() { return force_reply == typeof(force_reply).init; }
	deprecated typeof(this) get() { return this; }
}

struct ChatPhoto {
	string small_file_id,
			big_file_id;


@ignore @property:
	bool isNull() { return small_file_id == typeof(small_file_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct ChatMember {
	User user;
	string status;

@optional:
	long until_date;
	bool can_be_edited,
			can_change_info,
			can_post_messages,
			can_edit_messages,
			can_delete_messages,
			can_invite_users,
			can_restrict_members,
			can_pin_messages,
			can_promote_members,
			can_send_messages,
			can_send_media_messages,
			can_send_other_messages,
			can_add_web_page_previews;

@ignore @property:
	bool isNull() { return user.isNull; }
	deprecated typeof(this) get() { return this; }
}

struct ResponseParameters {
@optional:
	long migrate_to_chat_id;
	int retry_after;

@ignore @property:
	bool isNull() { return !migrate_to_chat_id && !retry_after; }
	deprecated typeof(this) get() { return this; }
}


private alias InputMediaStructs = AliasSeq!(InputMediaPhoto, InputMediaVideo, InputMediaAnimation, InputMediaAudio, InputMediaDocument);
alias InputMedia = Algebraic!InputMediaStructs;

struct InputMediaPhoto {
	string type = "photo";
	string media;

@optional:
	string caption;
	ParseMode parse_mode;

@ignore @property:
	bool isNull() { return media == typeof(media).init; }
	deprecated typeof(this) get() { return this; }
}

struct InputMediaVideo {
	string type = "video";
	string media;

@optional:
	string thumb;
	string caption;
	ParseMode parse_mode;
	int width,
		height,
		duration;
	bool supports_streaming;

@ignore @property:
	bool isNull() { return media == typeof(media).init; }
	deprecated typeof(this) get() { return this; }
}

struct InputMediaAnimation {
	string type = "animation";
	string media;

@optional:
	string thumb;
	string caption;
	ParseMode parse_mode;
	int width,
		height,
		duration;

@ignore @property:
	bool isNull() { return media == typeof(media).init; }
	deprecated typeof(this) get() { return this; }
}

struct InputMediaAudio {
	string type = "audio";
	string media;

@optional:
	string thumb;
	string caption;
	ParseMode parse_mode;
	int duration;
	string performer;
	string title;

@ignore @property:
	bool isNull() { return media == typeof(media).init; }
	deprecated typeof(this) get() { return this; }
}

struct InputMediaDocument {
	string type = "document";
	string media;

@optional:
	string thumb;
	string caption;
	ParseMode parse_mode;

@ignore @property:
	bool isNull() { return media == typeof(media).init; }
	deprecated typeof(this) get() { return this; }
}

struct Sticker {
	string file_id;
	int width,
		height;

@optional:
	PhotoSize thumb;
	string emoji,
			set_name;
	MaskPosition mask_position;
	int file_size;

@ignore @property:
	bool isNull() { return file_id == typeof(file_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct StickerSet {
	string name,
		   title;
	bool contains_masks;
	Sticker[] stickers;

@ignore @property:
	bool isNull() { return name == typeof(name).init; }
	deprecated typeof(this) get() { return this; }
}

struct MaskPosition {
	string point;
	float x_shift,
		  y_shift,
		  scale;

@ignore @property:
	bool isNull() { return point == typeof(point).init; }
	deprecated typeof(this) get() { return this; }
}

struct Game {
	string title,
		   description;
	PhotoSize[] photo;

@optional:
	string text;
	MessageEntity[] text_entities;
	Animation animation;

@ignore @property:
	bool isNull() { return title == typeof(title).init; }
	deprecated typeof(this) get() { return this; }
}

struct Animation {
	string file_id;

@optional:
	PhotoSize thumb;
	string file_name,
			mime_type;
	int file_size;

@ignore @property:
	bool isNull() { return file_id == typeof(file_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct CallbackGame {
@ignore @property:
	bool isNull() { return true; }
	deprecated typeof(this) get() { return this; }
}

struct GameHighScore {
	int position;
	User user;
	int score;

@ignore @property:
	bool isNull() { return position == typeof(position).init; }
	deprecated typeof(this) get() { return this; }
}

struct LabeledPrice {
	string label;
	int amount;

@ignore @property:
	bool isNull() { return label == typeof(label).init; }
	deprecated typeof(this) get() { return this; }
}

struct Invoice {
	string title,
		   description,
		   start_parameter,
		   currency;
	int total_amount;

@ignore @property:
	bool isNull() { return title == typeof(title).init; }
	deprecated typeof(this) get() { return this; }
}

struct ShippingAddress {
	string country_code,
		   state,
		   city,
		   street_line1,
		   street_line2,
		   post_code;

@ignore @property:
	bool isNull() { return country_code == typeof(country_code).init; }
	deprecated typeof(this) get() { return this; }
}

struct OrderInfo {
@optional:
	string name,
			phone_number,
			email;
	ShippingAddress shipping_address;

@ignore @property:
	bool isNull() { return !name.length && !phone_number.length && !email.length && shipping_address.isNull; }
	deprecated typeof(this) get() { return this; }
}

struct ShippingOption {
	string id,
		   title;
	LabeledPrice[] prices;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct SuccessfulPayment {
	string currency;
	int total_amount;
	string invoice_payload,
		   telegram_payment_charge_id,
		   provider_payment_charge_id;

@optional:
	string shipping_option_id;
	OrderInfo order_info;

@ignore @property:
	bool isNull() { return currency == typeof(currency).init; }
	deprecated typeof(this) get() { return this; }
}

struct ShippingQuery {
	string id;
	User from;
	string invoice_payload;
	ShippingAddress shipping_address;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct PreCheckoutQuery {
	string id;
	User from;
	string currency;
	int total_amount;
	string invoice_payload;

@optional:
	string shipping_option_id;
	OrderInfo order_info;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQuery {
	string id;
	User from;
	string query,
		   offset;

@optional:
	Location location;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

private alias InlineQueryResultStructs = AliasSeq!(InlineQueryResultArticle, InlineQueryResultPhoto,
		InlineQueryResultGif, InlineQueryResultMpeg4Gif, InlineQueryResultVideo,
		InlineQueryResultAudio, InlineQueryResultVoice, InlineQueryResultDocument,
		InlineQueryResultLocation,
		InlineQueryResultVenue,
		InlineQueryResultContact,
		InlineQueryResultGame, InlineQueryResultCachedPhoto, InlineQueryResultCachedGif,
		InlineQueryResultCachedMpeg4Gif, InlineQueryResultCachedSticker, InlineQueryResultCachedDocument,
		InlineQueryResultCachedVideo, InlineQueryResultCachedVoice, InlineQueryResultCachedAudio);

alias InlineQueryResult = Algebraic!InlineQueryResultStructs;

struct InlineQueryResultArticle {
	string type = "article";
	string id;
	string title;
	InputMessageContent input_message_content;

@optional:
	InlineKeyboardMarkup reply_markup;
	string url;
	bool hide_url;
	string description;
	string thumb_url;
	int thumb_width;
	int thumb_height;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultPhoto {
	string type = "photo";
	string id;
	string photo_url;
	string thumb_url;

@optional:
	int photo_width;
	int photo_height;
	string title;
	string description;
	string caption;
	ParseMode parse_mode;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultGif {
	string type = "gif";
	string id;
	string gif_url;
	string thumb_url;

@optional:
	int gif_width;
	int gif_height;
	int gif_duration;
	string title;
	string caption;
	ParseMode parse_mode;
	InputMessageContent input_message_content;
	InlineKeyboardMarkup reply_markup;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultMpeg4Gif{
	string type = "mpeg4_gif";
	string id;
	string mpeg4_url;
	int mpeg4_width;
	int mpeg4_height;
	int mpeg4_duration;
	string thumb_url;

@optional:
	string title;
	string caption;
	ParseMode parse_mode;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultVideo {
	string type = "video";
	string id;
	string video_url;
	string mime_type;
	string thumb_url;
	string title;

@optional:
	string caption;
	ParseMode parse_mode;
	int video_width;
	int video_height;
	int video_duration;
	string description;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultAudio {
	string type = "audio";
	string id;
	string audio_url;
	string title;

@optional:
	string caption;
	ParseMode parse_mode;
	string performer;
	int audio_duration;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultVoice {
	string type = "voice";
	string id;
	string voice_url;
	string title;

@optional:
	string caption;
	ParseMode parse_mode;
	int voice_duration;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultDocument {
	string type = "document";
	string id;
	string title;
	string document_url;
	string mime_type;

@optional:
	string caption;
	ParseMode parse_mode;
	string description;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;
	string thumb_url;
	int thumb_width;
	int thumb_height;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultLocation {
	string type = "location";
	string id;
	float latitude;
	float longitude;
	string title;

@optional:
	int live_period;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;
	string thumb_url;
	int thumb_width;
	int thumb_height;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultVenue {
	string type = "venue";
	string id;
	float latitude;
	float longitude;
	string title;
	string address;

@optional:
	string foursquare_id;
	string foursquare_type;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;
	string thumb_url;
	int thumb_width;
	int thumb_height;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultContact {
	string type = "contact";
	string id;
	string phone_number;
	string first_name;

@optional:
	string last_name;
	string vcard;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;
	string thumb_url;
	int thumb_width;
	int thumb_height;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultGame {
	string type = "game";
	string id;
	string game_short_name;

@optional:
	InlineKeyboardMarkup reply_markup;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultCachedPhoto {
	string type = "photo";
	string id;
	string photo_file_id;

@optional:
	string title;
	string description;
	string caption;
	ParseMode parse_mode;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultCachedGif{
	string type = "gif";
	string id;
	string gif_file_id;

@optional:
	string title;
	string caption;
	ParseMode parse_mode;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultCachedMpeg4Gif{
	string type = "mpeg4_gif";
	string id;
	string mpeg4_file_id;

@optional:
	string title;
	string caption;
	ParseMode parse_mode;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultCachedSticker {
	string type = "sticker";
	string id;
	string sticker_file_id;

@optional:
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultCachedDocument {
	string type = "document";
	string id;
	string title;
	string document_file_id;

@optional:
	string description;
	string caption;
	ParseMode parse_mode;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultCachedVideo {
	string type = "video";
	string id;
	string video_file_id;
	string title;

@optional:
	string description;
	string caption;
	ParseMode parse_mode;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultCachedVoice {
	string type = "voice";
	string id;
	string voice_file_id;
	string title;

@optional:
	string caption;
	ParseMode parse_mode;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

struct InlineQueryResultCachedAudio {
	string type = "audio";
	string id;
	string audio_file_id;

@optional:
	string caption;
	ParseMode parse_mode;
	InlineKeyboardMarkup reply_markup;
	InputMessageContent input_message_content;

@ignore @property:
	bool isNull() { return id == typeof(id).init; }
	deprecated typeof(this) get() { return this; }
}

private alias InputMessageContentStructs = AliasSeq!(InputTextMessageContent,
		InputLocationMessageContent, InputVenueMessageContent, InputContactMessageContent);

alias InputMessageContent = Algebraic!InputMessageContentStructs;

struct InputTextMessageContent {
	string message_text;

@optional:
	ParseMode parse_mode;
	bool disable_web_page_preview;

@ignore @property:
	bool isNull() { return message_text == typeof(message_text).init; }
	deprecated typeof(this) get() { return this; }
}

struct InputLocationMessageContent {
	float latitude;
	float longitude;

@optional:
	int live_period;

@ignore @property:
	bool isNull() { return latitude.isNaN; }
	deprecated typeof(this) get() { return this; }
}

struct InputVenueMessageContent {
	float latitude;
	float longitude;
	string title;
	string address;

@optional:
	string foursquare_id;
	string foursquare_type;

@ignore @property:
	bool isNull() { return latitude.isNaN; }
	deprecated typeof(this) get() { return this; }
}

struct InputContactMessageContent {
	string phone_number;
	string first_name;

@optional:
	string last_name;
	string vcard;

@ignore @property:
	bool isNull() { return phone_number == typeof(phone_number).init; }
	deprecated typeof(this) get() { return this; }
}

struct ChosenInlineResult {
	string result_id;
	User from;
	string query;

@optional:
	Location location;
	string inline_message_id;

@ignore @property:
	bool isNull() { return result_id == typeof(result_id).init; }
	deprecated typeof(this) get() { return this; }
}

struct WebhookInfo {
	string url;
	bool has_custom_certificate;
	int pending_update_count;

@optional:
	long last_error_date;
	string last_error_message;
	int max_connections;
	string[] allowed_updates;

@ignore @property:
	bool isNull() { return url == typeof(url).init; }
	deprecated typeof(this) get() { return this; }
}

/*                        Telegram methods                        */

mixin template TelegramMethod(string path) {
	package @ignore immutable string m_path = path;
}

alias TelegramID = Algebraic!(long, string);
enum isTelegramID(T) = is(T : long) || is(T == string);

struct GetUpdatesMethod {
	mixin TelegramMethod!"/getUpdates";

@optional:
	int offset;
	int limit = 100;
	int timeout = 0;
	string[] allowed_updates = [];
}

struct SetWebhookMethod {
	mixin TelegramMethod!"/setWebhook";

	string url;

@optional:
	InputFile certificate;
	int max_connections = 40;
	string[] allowed_updates = [];
}

struct DeleteWebhookMethod {
	mixin TelegramMethod!"/deleteWebhook";
}

struct GetWebhookInfoMethod {
	mixin TelegramMethod!"/getWebhookInfo";
}

struct GetMeMethod {
	mixin TelegramMethod!"/getMe";
}

struct SendMessageMethod {
	mixin TelegramMethod!"/sendMessage";

	TelegramID chat_id;
	string text;

@optional:
	ParseMode parse_mode;
	bool disable_web_page_preview;
	bool disable_notification;
	int reply_to_message_id;

	ReplyMarkup reply_markup;
}

struct ForwardMessageMethod {
	mixin TelegramMethod!"/forwardMessage";

	TelegramID chat_id;
	TelegramID from_chat_id;
@optional bool disable_notification;
	int message_id;
}

struct SendPhotoMethod {
	mixin TelegramMethod!"/sendPhoto";

	TelegramID chat_id;
	string photo;

@optional:
	string caption;
	ParseMode parse_mode;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendAudioMethod {
	mixin TelegramMethod!"/sendAudio";

	TelegramID chat_id;
	string audio;

@optional:
	string caption;
	ParseMode parse_mode;
	int duration;
	string performer;
	string title;
	string thumb;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;

}

struct SendAnimationMethod {
	mixin TelegramMethod!"/sendAnimation";

	TelegramID chat_id;
	string animation;

@optional:
	int duration,
		width,
		height;
	string thumb;
	string caption;
	ParseMode parse_mode;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendDocumentMethod {
	mixin TelegramMethod!"/sendDocument";

	TelegramID chat_id;
	string document;

@optional:
	string thumb;
	string caption;
	ParseMode parse_mode;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendVideoMethod {
	mixin TelegramMethod!"/sendVideo";

	TelegramID chat_id;
	string video;

@optional:
	int duration;
	int width;
	int height;
	string thumb;
	string caption;
	ParseMode parse_mode;
	bool supports_streaming;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendVoiceMethod {
	mixin TelegramMethod!"/sendVoice";

	TelegramID chat_id;
	string voice;

@optional:
	string caption;
	ParseMode parse_mode;
	int duration;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendVideoNoteMethod {
	mixin TelegramMethod!"/sendVideoNote";

	TelegramID chat_id;
	string video_note;

@optional:
	int duration;
	int length;
	string thumb;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;

}

struct SendMediaGroupMethod {
	mixin TelegramMethod!"/sendMediaGroup";

	TelegramID chat_id;
	Algebraic!(InputMediaPhoto, InputMediaVideo)[] media;

@optional:
	bool disable_notification;
	int reply_to_message_id;
}

struct SendLocationMethod {
	mixin TelegramMethod!"/sendLocation";

	TelegramID chat_id;
	float latitude;
	float longitude;

@optional:
	int live_period;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct EditMessageLiveLocationMethod {
	mixin TelegramMethod!"/editMessageLiveLocation";

	float latitude;
	float longitude;

@optional:
	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	ReplyMarkup reply_markup;
}

struct StopMessageLiveLocationMethod {
	mixin TelegramMethod!"/stopMessageLiveLocation";

@optional:

	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	ReplyMarkup reply_markup;
}

struct SendVenueMethod {
	mixin TelegramMethod!"/sendVenue";

	TelegramID chat_id;
	float latitude;
	float longitude;
	string title;
	string address;

@optional:
	string foursquare_id;
	string foursquare_type;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendContactMethod {
	mixin TelegramMethod!"/sendContact";

	TelegramID chat_id;
	string phone_number;
	string first_name;

@optional:
	string last_name;
	string vcard;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendChatActionMethod {
	mixin TelegramMethod!"/sendChatAction";

	TelegramID chat_id;
	string action; // TODO enum
}

struct GetUserProfilePhotosMethod {
	mixin TelegramMethod!"/getUserProfilePhotos";

	int user_id;

@optional:
	int offset;
	int limit;
}

struct GetFileMethod {
	mixin TelegramMethod!"/getFile";

	string file_id;
}

struct KickChatMemberMethod {
	mixin TelegramMethod!"/kickChatMember";

	TelegramID chat_id;
	int user_id;

@optional:
	int until_date;
}

struct UnbanChatMemberMethod {
	mixin TelegramMethod!"/unbanChatMember";

	TelegramID chat_id;
	int user_id;
}

struct RestrictChatMemberMethod {
	mixin TelegramMethod!"/restrictChatMember";

	TelegramID chat_id;
	int user_id;

@optional:
	int until_date;
	bool can_send_messages;
	bool can_send_media_messages;
	bool can_send_other_messages;
	bool can_add_web_page_previews;
}

struct PromoteChatMemberMethod {
	mixin TelegramMethod!"/promoteChatMember";

	TelegramID chat_id;
	int user_id;

@optional:
	bool can_change_info;
	bool can_post_messages;
	bool can_edit_messages;
	bool can_delete_messages;
	bool can_invite_users;
	bool can_restrict_members;
	bool can_pin_messages;
	bool can_promote_members;
}

struct ExportChatInviteLinkMethod {
	mixin TelegramMethod!"/exportChatInviteLink";

	TelegramID chat_id;
}

struct SetChatPhotoMethod {
	mixin TelegramMethod!"/setChatPhoto";

	TelegramID chat_id;
	InputFile photo;

}

struct DeleteChatPhotoMethod {
	mixin TelegramMethod!"/deleteChatPhoto";

	TelegramID chat_id;
}

struct SetChatTitleMethod {
	mixin TelegramMethod!"/setChatTitle";

	TelegramID chat_id;
	string title;
}

struct SetChatDescriptionMethod {
	mixin TelegramMethod!"/setChatDescription";

	TelegramID chat_id;

@optional:
	string description;
}

struct PinChatMessageMethod {
	mixin TelegramMethod!"/pinChatMessage";

	TelegramID chat_id;
	int message_id;

@optional:
	bool disable_notification;
}

struct UnpinChatMessageMethod {
	mixin TelegramMethod!"/unpinChatMessage";

	TelegramID chat_id;
}

struct LeaveChatMethod {
	mixin TelegramMethod!"/leaveChat";

	TelegramID chat_id;
}

struct GetChatMethod {
	mixin TelegramMethod!"/getChat";

	TelegramID chat_id;
}

struct GetChatAdministratorsMethod {
	mixin TelegramMethod!"/getChatAdministrators";

	TelegramID chat_id;
}

struct GetChatMembersCountMethod {
	mixin TelegramMethod!"/getChatMembersCount";

	TelegramID chat_id;
}

struct GetChatMemberMethod {
	mixin TelegramMethod!"/getChatMember";

	TelegramID chat_id;
	int user_id;
}

struct SetChatStickerSetMethod {
	mixin TelegramMethod!"/setChatStickerSet";

	TelegramID chat_id;
	string sticker_set_name;
}

struct DeleteChatStickerSetMethod {
	mixin TelegramMethod!"/deleteChatStickerSet";

	TelegramID chat_id;
}

struct AnswerCallbackQueryMethod {
	mixin TelegramMethod!"/answerCallbackQuery";

	string callback_query_id;

@optional:
	string text;
	bool show_alert;
	string url;
	int cache_time;
}

struct EditMessageTextMethod {
	mixin TelegramMethod!"/editMessageText";

	string text;

@optional:
	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	ParseMode parse_mode;
	bool disable_web_page_preview;
	ReplyMarkup reply_markup;
}

struct EditMessageCaptionMethod {
	mixin TelegramMethod!"/editMessageCaption";

@optional:
	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	string caption;
	ParseMode parse_mode;
	ReplyMarkup reply_markup;
}

struct EditMessageReplyMarkupMethod {
	mixin TelegramMethod!"/editMessageReplyMarkup";

@optional:
	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	ReplyMarkup reply_markup;
}

struct EditMessageMediaMethod {
	mixin TelegramMethod!"/editMessageMedia";

	InputMedia media;

@optional:
	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	ReplyMarkup reply_markup;
}

struct DeleteMessageMethod {
	mixin TelegramMethod!"/deleteMessage";

	TelegramID chat_id;
	int message_id;
}

struct SendStickerMethod {
	mixin TelegramMethod!"/sendSticker";

	TelegramID chat_id;
	string sticker; // TODO InputFile|string

@optional:
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct GetStickerSetMethod {
	mixin TelegramMethod!"/getStickerSet";

	string name;
}

struct UploadStickerFileMethod {
	mixin TelegramMethod!"/uploadStickerFile";

	int user_id;
	InputFile png_sticker;
}

struct CreateNewStickerSetMethod {
	mixin TelegramMethod!"/createNewStickerSet";

	int user_id;
	string name;
	string title;
	string png_sticker; // TODO InputFile|string
	string emojis;

@optional:
	bool contains_masks;
	MaskPosition mask_position;
}

struct AddStickerToSetMethod {
	mixin TelegramMethod!"/addStickerToSet";

	int user_id;
	string name;
	string png_sticker; // TODO InputFile|string
	string emojis;

@optional:
	MaskPosition mask_position;
}

struct SetStickerPositionInSetMethod {
	mixin TelegramMethod!"/setStickerPositionInSet";

	string sticker;
	int position;
}

struct DeleteStickerFromSetMethod {
	mixin TelegramMethod!"/deleteStickerFromSet";

	string sticker;
}

struct AnswerInlineQueryMethod {
	mixin TelegramMethod!"/answerInlineQuery";

	string inline_query_id;
	InlineQueryResult[] results;

@optional:
	int cache_time;
	bool is_personal;
	string next_offset;
	string switch_pm_text;
	string switch_pm_parameter;
}

private:

enum optional;
enum ignore;
struct name {
	string name;
}

import std.variant : Algebraic, VariantN;
@trusted Json serializeToJson(T)(T value) {
	import std.traits;
	static if(is(T : Json)) {
		return value;
	} else static if(isInstanceOf!(VariantN, T)) {
		if(!value.hasValue)
			return Json.emptyObject;

		static foreach(Type; value.AllowedTypes)
			if(value.type == typeid(Type))
				return value.get!Type.serializeToJson;

		return Json(null);
	} else static if(is(T == struct)) {
		auto ret = Json.emptyObject;
		foreach(i, ref field; value.tupleof) {
			if(hasUDA!(value.tupleof[i], ignore) || (hasUDA!(value.tupleof[i], optional) && !field.shouldSerialize)) {
				continue;
			} else {
				enum udas = getUDAs!(value.tupleof[i], name);
				static if(udas.length) {
					ret[udas[0].name] = field.serializeToJson;
				} else {
					ret[__traits(identifier, value.tupleof[i])] = field.serializeToJson;
				}
			}
		}
		return ret;
	} else static if(isArray!T && !is(T : string)) {
		auto ret = Json.emptyArray;
		foreach(i; value) {
			ret.appendArrayElement(i.serializeToJson);
		}
		return ret;
	} else {
		return Json(value);
	}
}

@trusted bool shouldSerialize(T)(T value) {
	static if(__traits(compiles, value.isNull)) {
		return !value.isNull;
	} else static if(__traits(compiles, value.hasValue)) {
		return value.hasValue;
	} else {
		return value != typeof(value).init;
	}
}

@("serializeToJson serializes simple values")
unittest {
	"Hey".serializeToJson.should.be.equal(Json("Hey"));
	42.serializeToJson.should.be.equal(Json(42));
	null.serializeToJson.should.be.equal(Json(null));
}

@("serializeToJson serializes structures and arrays")
unittest {
	struct S {
		int n;
		string t;
	}
	S(42, "text").serializeToJson.should.be.equal(Json([
		"n": Json(42),
		"t": Json("text"),
	]));

	["hey", "you"].serializeToJson.should.be.equal(Json([Json("hey"), Json("you")]));
	[S(41, "text1"), S(42, "text2")].serializeToJson.should.be.equal(Json([
		Json([
			"n": Json(41),
			"t": Json("text1")
		]),
		Json([
			"n": Json(42),
			"t": Json("text2")
		]),
	]));

	struct S2 {
		int n;
	}

	struct S1 {
		S2 s2;
	}
	S1(S2(42)).serializeToJson.should.be.equal(Json(["s2": Json(["n": Json(42)])]));

	[
		[41, 42],
		[43, 44],
	].serializeToJson.should.be.equal(Json([
		Json([
			Json(41), Json(42),
		]),
		Json([
			Json(43), Json(44),
		]),
	]));
}

@("serializeToJson ignores `@ignore` fields")
unittest {
	struct S {
		@ignore int n;
		string t;
	}
	S(42, "text").serializeToJson.should.be.equal(Json(["t": Json("text")]));

	struct S2 {
		int n;
		@ignore string t;
	}

	struct S1 {
		S2 s2;
	}
	S1(S2(42, "text")).serializeToJson.should.be.equal(Json(["s2": Json(["n": Json(42)])]));
}

@("serializeToJson ignores `@optional` fields when their value is equal to `typeof(field).init`")
unittest {
	struct S {
		@optional @name("i") int n;
		string t;
	}

	S(int.init, "text").serializeToJson.should.be.equal(Json(["t": Json("text")]));
	S(42, "text").serializeToJson.should.be.equal(Json(["i": Json(42), "t": Json("text")]));


	struct S2 {
		int n;
		@optional string t;
	}

	struct S1 {
		S2 s2;
	}
	S1(S2(42)).serializeToJson.should.be.equal(Json(["s2": Json(["n": Json(42)])]));
	S1(S2(42, "text")).serializeToJson.should.be.equal(Json(["s2": Json(["n": Json(42), "t": Json("text")])]));
}

@("serializeToJson serializes Algebraic values")
unittest {
	struct S1 {
		int s1;
	}

	struct S2 {
		string s2;
	}

	Algebraic!(S1, S2)(S1(42)).serializeToJson.toString
		.should.be.equal(`{"s1":42}`);
	Algebraic!(S1, S2)(S2("hello")).serializeToJson.toString
		.should.be.equal(`{"s2":"hello"}`);
}

@("serializeToJson serializes complex structs")
unittest {
	auto data = Message(42, 0, Chat(1337, ChatType.group)).serializeToJson;

	data["message_id"].should.be.equal(Json(42));
	data["date"].should.be.equal(Json(0));
	data["chat"]["type"].should.be.equal(Json("group"));
	data["chat"]["id"].should.be.equal(Json(1337));
}

@trusted T deserializeJson(T)(Json value) {
	import std.traits;
	import std.exception;
	static if(is(T : Json)) {
		return value;
	} else static if(isInstanceOf!(VariantN, T)) {
		return T.init;
	} else static if(is(T == struct)) {
		enforce(value.type == Json.Type.object);
		T ret;
		foreach(i, ref field; ret.tupleof) {
			if(hasUDA!(ret.tupleof[i], ignore)) {
				continue;
			} else {
				enum udas = getUDAs!(ret.tupleof[i], name);
				static if(udas.length) {
					if(value[udas[0].name].type == Json.Type.undefined) {
						static if(!hasUDA!(ret.tupleof[i], optional))
							throw new Exception("Missing value for non-optional field "~ udas[0].name);
					} else {					
						field = value[udas[0].name].deserializeJson!(typeof(field));
					}
				} else {
					if(value[__traits(identifier, ret.tupleof[i])].type == Json.Type.undefined) {
						static if(!hasUDA!(ret.tupleof[i], optional))
							throw new Exception("Missing value for non-optional field "~ __traits(identifier, ret.tupleof[i]));
					} else {					
						field = value[__traits(identifier, ret.tupleof[i])].deserializeJson!(typeof(field));
					}
				}
			}
		}
		return ret;
	} else static if(isArray!T && !is(T : string)) {
		enforce(value.type == Json.Type.array);
		T ret;
		foreach(ref e; value)
			ret ~= e.deserializeJson!(ForeachType!T);
		
		return ret;
	} else static if(is(T == enum)) {
		enforce(value.type == Json.Type.string);
		auto tmp = value.deserializeJson!string;

		switch(tmp) {
		static foreach(member; EnumMembers!T) {
			case member: {
				return member;
			}
		}
		default:
			assert(0);
		}
	} else {
		return value.get!T;
	}
}

@("deserializeJson deserializes simple values")
unittest {
	Json("hey").deserializeJson!string.should.be.equal("hey");
	Json(42).deserializeJson!int.should.be.equal(42);
	Json([
		Json(42),
		Json(43),
	]).deserializeJson!(int[]).should.be.equal([42, 43]);
}

@("deserializeJson deserializes structs")
unittest {
	struct S {
		int n;
		string t;
	}

	Json([
		"n": Json(42),
		"t": Json("text"),
	]).deserializeJson!S.should.be.equal(S(42, "text"));
}