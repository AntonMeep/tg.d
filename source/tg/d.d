/**
 * Tg.d is a D client library for Telegram Bot API
 *
 * Authors: Anton Fediushin, Pavel Chebotarev
 * Licence: MIT, see LICENCE
 * Copyright: Copyright for portions of project tg.d are held by Pavel Chebotarev, 2018 as part of project telega (https://github.com/nexor/telega). All other copyright for project tg.d are held by Anton Fediushin, 2018.
 * See_Also: $(LINK https://gitlab.com/ohboi/tg.d)
 */
module tg.d;

import std.traits : FieldNameTuple;
import std.typecons : Nullable;

import vibe.core.log;
import vibe.data.json;
import vibe.data.serialization : optional;

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
	private {
		string m_url;

		struct MethodResult(T) {
			bool ok;
		@optional:
			T result;
			ushort error_code;
			string description;
		}

		version(unittest) Json delegate(string, Json) @safe m_fakecall;
	}
@safe:

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
			Json j = Json.emptyObject;

			static foreach(field; FieldNameTuple!M)
				static if(field != "m_path")
					if(mixin("method." ~ field ~ " != typeof(method." ~ field ~ ").init"))
						j[field] = mixin("method." ~ field).serializeToJson;

			auto json = m_fakecall(m_url ~ method.m_path, j).deserializeJson!(MethodResult!T);

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

					Json j = Json.emptyObject;

					static foreach(field; FieldNameTuple!M)
						static if(field != "m_path")
							if(mixin("method." ~ field ~ " != typeof(method." ~ field ~ ").init"))
								j[field] = mixin("method." ~ field).serializeToJson;

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

	@("TelegramBot.getUpdates()")
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
		).getUpdates.serializeToJsonString.should.be.equal(`[]`);
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
	auto updateGetter(int timeout = 3, string[] allowed_updates = []) {
		struct updateGetterImpl {
			private {
				TelegramBot m_bot;
				Update[] m_buffer;
				size_t m_index;
				bool m_empty;

				int m_timeout;
				string[] m_allowed_updates;
			}

		@safe:
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


		return updateGetterImpl(this, timeout, allowed_updates);
	}

	@("TelegramBot.updateGetter() returns valid input range")
	unittest {
		import std.range : ElementType, isInputRange;
		import std.traits: ReturnType;
		static assert(isInputRange!(ReturnType!(TelegramBot.updateGetter)) == true);
		static assert(is(ElementType!(ReturnType!(TelegramBot.updateGetter)) == Update));
	}

	@("TelegramBot.updateGetter()")
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

		TelegramBot("TOKEN", fake).updateGetter()
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

	@("TelegramBot.getMe()")
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
		).getMe.serializeToJsonString.should.be.equal(
			`{"id":42,"is_bot":true,"first_name":"John","last_name":null,"username":null,"language_code":null}`
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
		).getMe.serializeToJsonString.should.be.equal(
			`{"id":42,"is_bot":false,"first_name":"John","last_name":"Smith","username":"js","language_code":"en-GB"}`
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

	@("TelegramBot.sendMessage()")
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
		).sendMessage(42L, "text").serializeToJsonString.should.be.equal(Message().serializeToJsonString);

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
		).sendMessage("@superchat", 123, "text").serializeToJsonString
			.should.be.equal(Message().serializeToJsonString);
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

	@("TelegramBot.forwardMessage()")
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
		).forwardMessage(42L, 43L, 1337).serializeToJsonString.should.be.equal(Message().serializeToJsonString);
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

	@("TelegramBot.sendPhoto()")
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
		).sendPhoto(42L, "https://example.com/dogs.jpg").serializeToJsonString.should.be.equal(Message().serializeToJsonString);
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

	@("TelegramBot.sendAudio()")
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
		).sendAudio(42L, "https://example.com/woof.mp3").serializeToJsonString.should.be.equal(Message().serializeToJsonString);
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

	@("TelegramBot.sendDocument()")
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
		).sendDocument(42L, "https://example.com/document.pdf").serializeToJsonString.should.be.equal(Message().serializeToJsonString);
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

	@("TelegramBot.sendVideo()")
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
		).sendVideo(42L, "https://example.com/video.mp4").serializeToJsonString.should.be.equal(Message().serializeToJsonString);
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

	@("TelegramBot.sendAnimation()")
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
		).sendAnimation(42L, "https://example.com/me.gif").serializeToJsonString.should.be.equal(Message().serializeToJsonString);
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

	@("TelegramBot.sendVoice()")
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
		).sendVoice(42L, "https://example.com/voice.ogg").serializeToJsonString.should.be.equal(Message().serializeToJsonString);
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
	Message sendMediaGroup(T)(T chat_id, JsonableAlgebraic!(InputMediaPhoto, InputMediaVideo)[] media)
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
	 * Overloads either take `chat_id` and `message_id` or `inline_message_id`
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
	 * Overloads either take `chat_id` and `message_id` or `inline_message_id`
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
		return callMethod!(Nullable!Message)(m);
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

	bool unpinChatMessage(T)(T chat_id) if(isTelegramID!T) {
		UnpinChatMessageMethod m = {
			chat_id: chat_id,
		};

		return unpinChatMessage(m);
	}

	bool unpinChatMessage(UnpinChatMessageMethod m) {
		return callMethod!bool(m);
	}

	bool leaveChat(T)(T chat_id) if(isTelegramID!T) {
		LeaveChatMethod m = {
			chat_id: chat_id,
		};

		return leaveChat(m);
	}

	bool leaveChat(LeaveChatMethod m) {
		return callMethod!bool(m);
	}

	Chat getChat(T)(T chat_id) if(isTelegramID!T) {
		GetChatMethod m = {
			chat_id: chat_id,
		};

		return getChat(m);
	}

	Chat getChat(GetChatMethod m) {
		return callMethod!Chat(m);
	}

	ChatMember getChatAdministrators(T)(T chat_id) if(isTelegramID!T) {
		GetChatAdministratorsMethod m = {
			chat_id: chat_id,
		};

		return getChatAdministrators(m);
	}

	ChatMember getChatAdministrators(GetChatAdministratorsMethod m) {
		return callMethod!ChatMember(m);
	}

	int getChatMembersCount(T)(T chat_id) if(isTelegramID!T) {
		GetChatMembersCountMethod m = {
			chat_id: chat_id,
		};

		return getChatMembersCount(m);
	}

	int getChatMembersCount(GetChatMembersCountMethod m) {
		return callMethod!int(m);
	}

	ChatMember getChatMember(T)(T chat_id, int user_id) if(isTelegramID!T) {
		GetChatMemberMethod m = {
			user_id: user_id,
			chat_id: chat_id,
		};

		return getChatMember(m);
	}

	ChatMember getChatMember(GetChatMemberMethod m) {
		return callMethod!ChatMember(m);
	}

	bool setChatStickerSet(T)(T chat_id, string stickerSetName) if(isTelegramID!T) {
		SetChatStickerSetMethod m = {
			sticker_set_name: stickerSetName,
			chat_id: chat_id,
		};

		return setChatStickerSet(m);
	}

	bool setChatStickerSet(SetChatStickerSetMethod m) {
		return callMethod!bool(m);
	}

	bool deleteChatStickerSet(T)(T chat_id) if(isTelegramID!T) {
		DeleteChatStickerSetMethod m = {
			chat_id: chat_id,
		};

		return deleteChatStickerSet(m);
	}

	bool deleteChatStickerSet(DeleteChatStickerSetMethod m) {
		return callMethod!bool(m);
	}

	bool answerCallbackQuery(string callbackQueryId) {
		AnswerCallbackQueryMethod m = {
			callback_query_id: callbackQueryId,
		};

		return answerCallbackQuery(m);
	}

	bool answerCallbackQuery(AnswerCallbackQueryMethod m) {
		return callMethod!bool(m);
	}

	auto editMessageText(T)(T chat_id, int message_id, string text) if(isTelegramID!T) {
		EditMessageTextMethod m = {
			message_id: message_id,
			text: text,
			chat_id: chat_id,
		};

		return editMessageText(m);
	}

	auto editMessageText(string inline_message_id, string text) {
		EditMessageTextMethod m = {
			inline_message_id: inline_message_id,
			text: text,
		};

		return editMessageText(m);
	}

	auto editMessageText(EditMessageTextMethod m) {
		return callMethod!(JsonableAlgebraic!(Message, bool))(m);
	}

	auto editMessageCaption(T)(T chat_id, int message_id, string caption = null) if(isTelegramID!T) {
		EditMessageCaptionMethod m = {
			message_id: message_id,
			caption: caption,
			chat_id: chat_id,
		};

		return editMessageCaption(m);
	}

	auto editMessageCaption(string inline_message_id, string caption = null) {
		EditMessageCaptionMethod m = {
			inline_message_id: inline_message_id,
			caption: caption,
		};

		return editMessageCaption(m);
	}

	auto editMessageCaption(EditMessageCaptionMethod m) {
		return callMethod!(JsonableAlgebraic!(Message, bool))(m);
	}

	auto editMessageReplyMarkup(T)(T chat_id, int message_id, InlineKeyboardMarkup replyMarkup)
	if(isTelegramID!T) {
		EditMessageReplyMarkupMethod m = {
			message_id: message_id,
			chat_id: chat_id,
			reply_markup: replyMarkup,
		};

		m.reply_markup = replyMarkup;

		return editMessageReplyMarkup(m);
	}

	auto editMessageReplyMarkup(string inline_message_id, Nullable!ReplyMarkup replyMarkup) {
		EditMessageReplyMarkupMethod m = {
			inline_message_id: inline_message_id,
			reply_markup: replyMarkup,
		};

		return editMessageReplyMarkup(m);
	}

	auto editMessageReplyMarkup(EditMessageReplyMarkupMethod m) {
		return callMethod!(JsonableAlgebraic!(Message, bool))(m);
	}

	auto editMessageMedia(T)(T chat_id, int message_id, InputMedia media) {
		EditMessageMediaMethod m = {
			chat_id: chat_id,
			message_id: message_id,
			media: media,
		};
		return editMessageMedia(m);
	}

	auto editMessageMedia(string inline_message_id, InputMedia media) {
		EditMessageMediaMethod m = {
			inline_message_id: inline_message_id,
			media: media,
		};
		return editMessageMedia(m);
	}

	auto editMessageMedia(EditMessageMediaMethod m) {
		return callMethod!(JsonableAlgebraic!(Message, bool))(m);
	}

	bool deleteMessage(T)(T chat_id, int message_id) if(isTelegramID!T) {
		DeleteMessageMethod m = {
			message_id: message_id,
			chat_id: chat_id,
		};

		return deleteMessage(m);
	}

	bool deleteMessage(DeleteMessageMethod m) {
		return callMethod!bool(m);
	}

	// TODO sticker is InputFile|string
	Message sendSticker(T)(T chat_id, string sticker) if(isTelegramID!T) {
		SendStickerMethod m = {
			sticker: sticker,
			chat_id: chat_id,
		};

		return sendSticker(m);
	}

	Message sendSticker(SendStickerMethod m) {
		return callMethod!Message(m);
	}

	StickerSet getStickerSet(string name) {
		GetStickerSetMethod m = {
			name: name,
		};

		return getStickerSet(m);
	}

	StickerSet getStickerSet(GetStickerSetMethod m) {
		return callMethod!StickerSet(m);
	}

	File uploadStickerFile(int user_id, InputFile pngSticker) {
		UploadStickerFileMethod m = {
			user_id: user_id,
			png_sticker: pngSticker,
		};

		return uploadStickerFile(m);
	}

	File uploadStickerFile(UploadStickerFileMethod m) {
		return callMethod!File(m);
	}

	// TODO pngSticker is InputFile|string
	bool createNewStickerSet(int user_id,
		string name,
		string title,
		string pngSticker,
		string emojis) {
			CreateNewStickerSetMethod m = {
				user_id: user_id,
				name: name,
				title: title,
				png_sticker: pngSticker,
				emojis: emojis,
			};

			return createNewStickerSet(m);
	}

	bool createNewStickerSet(CreateNewStickerSetMethod m) {
		return callMethod!bool(m);
	}

	bool addStickerToSet(int user_id, string name, string pngSticker, string emojis) {
		AddStickerToSetMethod m = {
			user_id: user_id,
			name : name,
			png_sticker: pngSticker,
			emojis: emojis,
		};

		return addStickerToSet(m);
	}

	bool addStickerToSet(AddStickerToSetMethod m) {
		return callMethod!bool(m);
	}

	bool setStickerPositionInSet(string sticker, int position) {
		SetStickerPositionInSetMethod m = {
			sticker: sticker,
			position: position,
		};

		return setStickerPositionInSet(m);
	}

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
	Nullable!Message message,
					 edited_message,
					 channel_post,
					 edited_channel_post;
	Nullable!InlineQuery inline_query;
	Nullable!ChosenInlineResult chosen_inline_result;
	Nullable!CallbackQuery callback_query;
	Nullable!ShippingQuery shopping_query;
	Nullable!PreCheckoutQuery pre_checkout_query;
}

struct User {
	int id;
	bool is_bot;
	string first_name;
@optional:
	Nullable!string last_name,
					username,
					language_code;
}

struct Chat {
@safe:
	long id;
	ChatType type;
@optional:
	Nullable!string title,
					username,
					first_name,
					last_name;
	bool all_members_are_administrators;
	Nullable!ChatPhoto photo;
	Nullable!string description,
					invite_link;

	private @name("pinned_message") Json m_pinned_message;
	@property @ignore {
		Nullable!Message pinned_message() {
			return m_pinned_message.type == Json.Type.null_ 
					? Nullable!Message.init
					: Nullable!Message(m_pinned_message.deserializeJson!Message);
		}
		void pinned_message(Nullable!Message m) {
			if(!m.isNull)
				m_pinned_message = m.get.serializeToJson;
		}
	}

	Nullable!string sticker_set_name;
	bool can_set_sticker_set;
}

struct Message {
@safe:
	int message_id;

	@property @ignore {
		int  id()      { return message_id; }
		void id(int i) { message_id = i;    }
	}

	@optional Nullable!User from;
	long date;
	Chat chat;

@optional:
	Nullable!User forward_from;
	Nullable!Chat forward_from_chat;
	Nullable!int forward_from_message_id;
	Nullable!string forward_signature;
	Nullable!long forward_date;

	private @name("reply_to_message") Json m_reply_to_message;
	@property @ignore {
		Nullable!Message reply_to_message() {
			return m_reply_to_message.type == Json.Type.null_ 
					? Nullable!Message.init
					: Nullable!Message(m_reply_to_message.deserializeJson!Message);
		}
		void reply_to_message(Nullable!Message m) {
			if(!m.isNull)
				m_reply_to_message = m.get.serializeToJson;
		}
	}

	Nullable!long edit_date;
	Nullable!string media_group_id,
					author_signature,
					text;
	MessageEntity[] entities;
	MessageEntity[] caption_entities;
	Nullable!Audio audio;
	Nullable!Animation animation;
	Nullable!Document document;
	Nullable!Game game;
	PhotoSize[] photo;
	Nullable!Sticker sticker;
	Nullable!Video video;
	Nullable!Voice voice;
	Nullable!VideoNote video_note;
	Nullable!string caption;
	Nullable!Contact contact;
	Nullable!Location location;
	Nullable!Venue venue;
	User[] new_chat_members;
	Nullable!User left_chat_member;
	Nullable!string new_chat_title;
	PhotoSize[] new_chat_photo;
	bool delete_chat_photo,
				  group_chat_created,
				  supergroup_chat_created,
				  channel_chat_created;
	Nullable!long migrate_to_chat_id,
				  migrate_from_chat_id;

	private @name("pinned_message") Json m_pinned_message;
	@property @ignore {
		Nullable!Message pinned_message() {
			return m_pinned_message.type == Json.Type.null_ 
					? Nullable!Message.init
					: Nullable!Message(m_pinned_message.deserializeJson!Message);
		}
		void pinned_message(Nullable!Message m) {
			if(!m.isNull)
				m_pinned_message = m.get.serializeToJson;
		}
	}

	Nullable!Invoice invoice;
	Nullable!SuccessfulPayment successful_payment;
	Nullable!string connected_website;
}

struct MessageEntity {
	string type;
	int offset;
	int length;
@optional:
	Nullable!string url;
	Nullable!User user;
}

struct PhotoSize {
	string file_id;
	int width;
	int height;
@optional:
	Nullable!int file_size;
}

struct Audio {
	string file_id;
	int duration;
@optional:
	Nullable!string performer,
					title,
					mime_type;
	Nullable!int file_size;
	Nullable!PhotoSize thumb;
}

struct Document {
	string file_id;
@optional:
	Nullable!PhotoSize thumb;
	Nullable!string file_name,
					mime_type;
	Nullable!int file_size;
}

struct Video {
	string file_id;
	int width,
		height,
		duration;
@optional:
	Nullable!PhotoSize thumb;
	Nullable!string mime_type;
	Nullable!int file_size;
}

struct Voice {
	string file_id;
	int duration;
@optional:
	Nullable!string mime_type;
	Nullable!int file_size;
}

struct VideoNote {
	string file_id;
	int length,
		duration;
@optional:
	Nullable!PhotoSize thumb;
	Nullable!int file_size;
}

struct Contact {
	string phone_number,
		   first_name;
@optional:
	Nullable!string last_name;
	Nullable!int user_id;
	Nullable!string vcard;
}

struct Location {
	float longitude,
		  latitude;
}

struct Venue {
	Location location;
	string title,
		   address;
@optional:
	Nullable!string foursquare_id;
	Nullable!string foursquare_type;
}

struct UserProfilePhotos {
	int total_count;
	PhotoSize[] photos;
}

struct File {
	string file_id;
@optional:
	Nullable!int file_size;
	Nullable!string file_path;
}

private alias ReplyMarkupStructs = AliasSeq!(ReplyKeyboardMarkup, ReplyKeyboardRemove,
		InlineKeyboardMarkup, ForceReply);

/**
 Abstract structure for unioining ReplyKeyboardMarkup, ReplyKeyboardRemove,
 InlineKeyboardMarkup and ForceReply
*/
alias ReplyMarkup = JsonableAlgebraic!ReplyMarkupStructs;
enum isReplyMarkup(T) = is(T == ReplyMarkup) || staticIndexOf!(T, ReplyMarkupStructs) >= 0;

struct ReplyKeyboardMarkup {
	KeyboardButton[][] keyboard;
@optional:
	bool resize_keyboard,
				  one_time_keyboard,
				  selective;
}

struct KeyboardButton {
	string text;
@optional:
	bool request_contact,
				  request_location;
}

struct ReplyKeyboardRemove {
	bool remove_keyboard = true;
@optional:
	bool selective;
}

struct InlineKeyboardMarkup {
	InlineKeyboardButton[][] inline_keyboard;
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
}

struct CallbackQuery {
	string id;
	User from;
	string chat_instance;
@optional:
	Nullable!Message message;
	Nullable!string inline_message_id,
					data,
					game_short_name;
}

struct ForceReply {
	bool force_reply;
@optional:
	bool selective;
}

struct ChatPhoto {
	string small_file_id,
		   big_file_id;
}

struct ChatMember {
	User user;
	string status;
@optional:
	Nullable!long until_date;
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
}

struct ResponseParameters {
@optional:
	Nullable!long migrate_to_chat_id;
	Nullable!int retry_after;
}


private alias InputMediaStructs = AliasSeq!(InputMediaPhoto, InputMediaVideo, InputMediaAnimation, InputMediaAudio, InputMediaDocument);
alias InputMedia = JsonableAlgebraic!InputMediaStructs;

struct InputMediaPhoto {
	string type = "photo";
	string media;
@optional:
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
}

struct InputMediaVideo {
	string type = "video";
	string media;
@optional:
	Nullable!string thumb;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!int width,
				 height,
				 duration;
	bool supports_streaming;
}

struct InputMediaAnimation {
	string type = "animation";
	string media;
@optional:
	Nullable!string thumb;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!int width,
				 height,
				 duration;
}

struct InputMediaAudio {
	string type = "audio";
	string media;
@optional:
	Nullable!string thumb;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!int duration;
	Nullable!string performer;
	Nullable!string title;
}

struct InputMediaDocument {
	string type = "document";
	string media;
@optional:
	Nullable!string thumb;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
}

struct Sticker {
	string file_id;
	int width,
		height;
@optional:
	Nullable!PhotoSize thumb;
	Nullable!string emoji,
					set_name;
	Nullable!MaskPosition mask_position;
	Nullable!int file_size;
}

struct StickerSet {
	string name,
		   title;
	bool contains_masks;
	Sticker[] stickers;
}

struct MaskPosition {
	string point;
	float x_shift,
		  y_shift,
		  scale;
}

struct Game {
	string title,
		   description;
	PhotoSize[] photo;
@optional:
	Nullable!string text;
	MessageEntity[] text_entities;
	Nullable!Animation animation;
}

struct Animation {
	string file_id;
@optional:
	Nullable!PhotoSize thumb;
	Nullable!string file_name,
					mime_type;
	Nullable!int file_size;
}

struct CallbackGame {}

struct GameHighScore {
	int position;
	User user;
	int score;
}

struct LabeledPrice {
	string label;
	int amount;
}

struct Invoice {
	string title,
		   description,
		   start_parameter,
		   currency;
	int total_amount;
}

struct ShippingAddress {
	string country_code,
		   state,
		   city,
		   street_line1,
		   street_line2,
		   post_code;
}

struct OrderInfo {
@optional:
	Nullable!string name,
					phone_number,
					email;
	Nullable!ShippingAddress shipping_address;
}

struct ShippingOption {
	string id,
		   title;
	LabeledPrice[] prices;
}

struct SuccessfulPayment {
	string currency;
	int total_amount;
	string invoice_payload,
		   telegram_payment_charge_id,
		   provider_payment_charge_id;
@optional:
	Nullable!string shipping_option_id;
	Nullable!OrderInfo order_info;
}

struct ShippingQuery {
	string id;
	User from;
	string invoice_payload;
	ShippingAddress shipping_address;
}

struct PreCheckoutQuery {
	string id;
	User from;
	string currency;
	int total_amount;
	string invoice_payload;
@optional:
	Nullable!string shipping_option_id;
	Nullable!OrderInfo order_info;
}

struct InlineQuery {
	string id;
	User from;
	string query,
		   offset;
@optional:
	Nullable!Location location;
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

alias InlineQueryResult = JsonableAlgebraic!InlineQueryResultStructs;

struct InlineQueryResultArticle {
	string type = "article";
	string id;
	string title;
	InputMessageContent input_message_content;
@optional:
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!string url;
	bool hide_url;
	Nullable!string description;
	Nullable!string thumb_url;
	Nullable!int thumb_width;
	Nullable!int thumb_height;
}

struct InlineQueryResultPhoto {
	string type = "photo";
	string id;
	string photo_url;
	string thumb_url;
@optional:
	Nullable!int photo_width;
	Nullable!int photo_height;
	Nullable!string title;
	Nullable!string description;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultGif {
	string type = "gif";
	string id;
	string gif_url;
	string thumb_url;
@optional:
	Nullable!int gif_width;
	Nullable!int gif_height;
	Nullable!int gif_duration;
	Nullable!string title;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!InputMessageContent input_message_content;
	Nullable!InlineKeyboardMarkup reply_markup;
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
	Nullable!string title;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultVideo {
	string type = "video";
	string id;
	string video_url;
	string mime_type;
	string thumb_url;
	string title;
@optional:
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!int video_width;
	Nullable!int video_height;
	Nullable!int video_duration;
	Nullable!string description;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultAudio {
	string type = "audio";
	string id;
	string audio_url;
	string title;
@optional:
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!string performer;
	Nullable!int audio_duration;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultVoice {
	string type = "voice";
	string id;
	string voice_url;
	string title;
@optional:
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!int voice_duration;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultDocument {
	string type = "document";
	string id;
	string title;
	string document_url;
	string mime_type;
@optional:
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!string description;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
	Nullable!string thumb_url;
	Nullable!int thumb_width;
	Nullable!int thumb_height;
}

struct InlineQueryResultLocation {
	string type = "location";
	string id;
	float latitude;
	float longitude;
	string title;
@optional:
	Nullable!int live_period;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
	Nullable!string thumb_url;
	Nullable!int thumb_width;
	Nullable!int thumb_height;
}

struct InlineQueryResultVenue {
	string type = "venue";
	string id;
	float latitude;
	float longitude;
	string title;
	string address;
@optional:
	Nullable!string foursquare_id;
	Nullable!string foursquare_type;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
	Nullable!string thumb_url;
	Nullable!int thumb_width;
	Nullable!int thumb_height;
}

struct InlineQueryResultContact {
	string type = "contact";
	string id;
	string phone_number;
	string first_name;
@optional:
	Nullable!string last_name;
	Nullable!string vcard;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
	Nullable!string thumb_url;
	Nullable!int thumb_width;
	Nullable!int thumb_height;
}

struct InlineQueryResultGame {
	string type = "game";
	string id;
	string game_short_name;
	@optional Nullable!InlineKeyboardMarkup reply_markup;
}

struct InlineQueryResultCachedPhoto {
	string type = "photo";
	string id;
	string photo_file_id;
@optional:
	Nullable!string title;
	Nullable!string description;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultCachedGif{
	string type = "gif";
	string id;
	string gif_file_id;
@optional:
	Nullable!string title;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultCachedMpeg4Gif{
	string type = "mpeg4_gif";
	string id;
	string mpeg4_file_id;
@optional:
	Nullable!string title;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultCachedSticker {
	string type = "sticker";
	string id;
	string sticker_file_id;
@optional:
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultCachedDocument {
	string type = "document";
	string id;
	string title;
	string document_file_id;
@optional:
	Nullable!string description;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;;
}

struct InlineQueryResultCachedVideo {
	string type = "video";
	string id;
	string video_file_id;
	string title;
@optional:
	Nullable!string description;
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultCachedVoice {
	string type = "voice";
	string id;
	string voice_file_id;
	string title;
@optional:
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

struct InlineQueryResultCachedAudio {
	string type = "audio";
	string id;
	string audio_file_id;
@optional:
	Nullable!string caption;
	Nullable!ParseMode parse_mode;
	Nullable!InlineKeyboardMarkup reply_markup;
	Nullable!InputMessageContent input_message_content;
}

private alias InputMessageContentStructs = AliasSeq!(InputTextMessageContent,
		InputLocationMessageContent, InputVenueMessageContent, InputContactMessageContent);

alias InputMessageContent = JsonableAlgebraic!InputMessageContentStructs;

struct InputTextMessageContent {
	string message_text;
@optional:
	Nullable!ParseMode parse_mode;
	bool disable_web_page_preview;
}

struct InputLocationMessageContent {
	float latitude;
	float longitude;
@optional:
	Nullable!int live_period;
}

struct InputVenueMessageContent {
	float latitude;
	float longitude;
	string title;
	string address;
@optional:
	Nullable!string foursquare_id;
	Nullable!string foursquare_type;
}

struct InputContactMessageContent {
	string phone_number;
	string first_name;
@optional:
	Nullable!string last_name;
	Nullable!string vcard;
}

struct ChosenInlineResult {
	string result_id;
	User from;
	string query;
@optional:
	Nullable!Location location;
	Nullable!string inline_message_id;
}

struct WebhookInfo {
	string url;
	bool has_custom_certificate;
	int pending_update_count;
@optional:
	Nullable!long last_error_date;
	Nullable!string last_error_message;
	Nullable!int max_connections;
	string[] allowed_updates;
}

/******************************************************************/
/*                        Telegram methods                        */
/******************************************************************/

mixin template TelegramMethod(string path) {
package:
	immutable string m_path = path;
}

alias TelegramID = JsonableAlgebraic!(long, string);
enum isTelegramID(T) = is(T : long) || is(T == string);

struct GetUpdatesMethod {
	mixin TelegramMethod!"/getUpdates";

	int offset;
	int limit;
	int timeout;
	string[] allowed_updates;
}

struct SetWebhookMethod {
	mixin TelegramMethod!"/setWebhook";

	string url;
	Nullable!InputFile certificate;
	int max_connections;
	string[] allowed_updates;
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
	bool disable_notification;
	int message_id;
}

struct SendPhotoMethod {
	mixin TelegramMethod!"/sendPhoto";

	TelegramID chat_id;
	string photo;
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
	JsonableAlgebraic!(InputMediaPhoto, InputMediaVideo)[] media;
	bool disable_notification;
	int reply_to_message_id;
}

struct SendLocationMethod {
	mixin TelegramMethod!"/sendLocation";

	TelegramID chat_id;
	float latitude;
	float longitude;
	int live_period;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct EditMessageLiveLocationMethod {
	mixin TelegramMethod!"/editMessageLiveLocation";

	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	float latitude;
	float longitude;
	ReplyMarkup reply_markup;
}

struct StopMessageLiveLocationMethod {
	mixin TelegramMethod!"/stopMessageLiveLocation";

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
	string description;
}

struct PinChatMessageMethod {
	mixin TelegramMethod!"/pinChatMessage";

	TelegramID chat_id;
	int message_id;
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
	string text;
	bool show_alert;
	string url;
	int cache_time;
}

struct EditMessageTextMethod {
	mixin TelegramMethod!"/editMessageText";

	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	string text;
	ParseMode parse_mode;
	bool disable_web_page_preview;
	ReplyMarkup reply_markup;
}

struct EditMessageCaptionMethod {
	mixin TelegramMethod!"/editMessageCaption";

	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	string caption;
	ParseMode parse_mode;
	ReplyMarkup reply_markup;
}

struct EditMessageReplyMarkupMethod {
	mixin TelegramMethod!"/editMessageReplyMarkup";

	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	ReplyMarkup reply_markup;
}

struct EditMessageMediaMethod {
	mixin TelegramMethod!"/editMessageMedia";

	TelegramID chat_id;
	int message_id;
	string inline_message_id;
	InputMedia media;
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
	bool contains_masks;
	MaskPosition mask_position;
}

struct AddStickerToSetMethod {
	mixin TelegramMethod!"/addStickerToSet";

	int user_id;
	string name;
	string png_sticker; // TODO InputFile|string
	string emojis;
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
	int cache_time;
	bool is_personal;
	string next_offset;
	string switch_pm_text;
	string switch_pm_parameter;
}

// In short, this is an Algebraic type which can be Json serialized/deserialized
// While serialization works for any `Types`, deserialization is a bit tricky
// It will work *only* if there's only one struct in the list
// i.e. JsonableAlgebraic!(S1, bool, int) will work and JsonableAlgebraic!(S1, S2) won't
// This is more than enough for the Telegram's bot API though
private struct JsonableAlgebraic(Types...) {
@trusted:
	import std.meta;
	import std.variant : Algebraic;

	private {
		Algebraic!Types m_algebraic;
	}

	@property const auto algebraicOf() { return m_algebraic; }

	alias algebraicOf this;

	this(T)(T t) if(m_algebraic.allowed!T) {
		m_algebraic = typeof(m_algebraic)(t);
	}

	const bool opEquals(typeof(this) rhs) {
		return m_algebraic == rhs.m_algebraic;
	}

	void opAssign(T)(T rhs) if(m_algebraic.allowed!T) {
		m_algebraic = rhs;
	}

	void opAssign(typeof(this) rhs) {
		m_algebraic = rhs.m_algebraic;
	}

	const Json toJson() {
		if(!m_algebraic.hasValue)
			return Json.emptyObject;

		static foreach(T; Types)
			if(m_algebraic.type == typeid(T))
				return m_algebraic.get!T.serializeToJson;

		return Json(null);
	}

	static typeof(this) fromJson(Json src) {
		import std.traits : isAggregateType;
		static foreach(T; Types) {
			static if(isAggregateType!T) {
				if(src.type == Json.Type.object)
					return typeof(this)(src.deserializeJson!T);
			} else {
				if(src.type == Json.typeId!T)
					return typeof(this)(src.deserializeJson!T);
			}
		}
		return typeof(this).init;
	}
}

@("JsonableAlgebraic works for multiple structs")
unittest {
	struct S1 {
		int s1;
	}

	struct S2 {
		string s2;
	}

	JsonableAlgebraic!(S1, S2)(S1(42)).serializeToJsonString
		.should.be.equal(`{"s1":42}`);
	JsonableAlgebraic!(S1, S2)(S2("hello")).serializeToJsonString
		.should.be.equal(`{"s2":"hello"}`);
}

@("JsonableAlgebraic is @safe")
@safe unittest {
	struct S1 {
		JsonableAlgebraic!(int, bool) a;
	}

	S1 s1;

	static assert(__traits(compiles, () @safe { s1.a = JsonableAlgebraic!(int, bool)(42); }));
	static assert(__traits(compiles, () @safe { JsonableAlgebraic!(int, bool) b = 42; }));
}

@("JsonableAlgebraic works as a field in another struct")
unittest {
	struct S1 {
		int s1;
	}

	struct S2 {
		string s2;
	}

	struct Aggregate {
		JsonableAlgebraic!(S1, S2) aggregate;
	}

	Aggregate(JsonableAlgebraic!(S1, S2)(S1(42))).serializeToJsonString
		.should.be.equal(`{"aggregate":{"s1":42}}`);
	Aggregate(JsonableAlgebraic!(S1, S2)(S2("hello"))).serializeToJsonString
		.should.be.equal(`{"aggregate":{"s2":"hello"}}`);
}

@("JsonableAlgebraic can be used for simple deserialization")
unittest {
	struct S1 {
		int s1;
	}

	`{"s1":42}`.deserializeJson!(JsonableAlgebraic!(S1, bool))
		.should.be.equal(JsonableAlgebraic!(S1, bool)(S1(42)));
	`false`.deserializeJson!(JsonableAlgebraic!(S1, bool))
		.should.be.equal(JsonableAlgebraic!(S1, bool)(false));
}

@("JsonableAlgebraic supports useful methods of Algebraic type")
unittest {
	JsonableAlgebraic!(int, bool)(true).type.should.be.equal(typeid(bool));
	JsonableAlgebraic!(int, bool, float)(0.0f).type.should.be.equal(typeid(float));
	JsonableAlgebraic!(int, string)("hello").get!string.should.be.equal("hello");
}