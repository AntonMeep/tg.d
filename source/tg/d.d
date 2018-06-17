module tg.d;

import vibe.http.client;
import vibe.stream.operations;
import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.data.serialization : optional;
import std.conv;
import std.typecons;
import std.exception;
import std.traits;

import std.meta : AliasSeq, staticIndexOf;
import std.variant : Algebraic;


version(TgD_Verbose) {
	pragma(msg, "tg.d | Warning! tg.d is compiled in verbose mode where user data can end up in logs");
	pragma(msg, "tg.d | DISABLE THIS in production builds!");
}

class TelegramBotException : Exception {
	ushort code;

	this(ushort code, string description, string file = __FILE__,
			size_t line = __LINE__, Throwable next = null) @nogc @safe pure nothrow {
		this.code = code;
		super(description, file, line, next);
	}
}

struct TelegramBot {
	private {
		string baseUrl = "https://api.telegram.org/bot";
		string apiUrl;

		struct MethodResult(T) {
			bool ok;
		@optional:
			T result;
			ushort error_code;
			string description;
		}
	}

	this(string token) {
		this.apiUrl = baseUrl ~ token;
	}

	private T callMethod(T, M)(M method) {
		import vibe.data.json : serializeToJson;

		T result;

		"tg.d | Requesting %s".logDiagnostic(method._path);

		requestHTTP(apiUrl ~ method._path,
			(scope req) {
				req.method = method._httpMethod;
				if(method._httpMethod == HTTPMethod.POST) {
					version(TgD_Verbose)
						"tg.d | Sending body: %s".logDebug(method.serializeToJson);
					req.writeJsonBody(method.serializeToJson);
				}
			},
			(scope res) {
				auto answer = res.readJson;
				version(TgD_Verbose) {
					"tg.d | Response headers: %s".logDebug(res.headers);
					"tg.d | Response data: %s".logDiagnostic(answer);
				}

				auto json = answer.deserializeJson!(MethodResult!T);

				enforce(json.ok == true,
					new TelegramBotException(json.error_code, json.description));

				result = json.result;
			}
		);

		return result;
	}

	Update[] getUpdates(int offset = 0, int limit = 100, int timeout = 30, string[] allowed_updates = []) {
		GetUpdatesMethod m = {
			offset: offset,
			limit: limit,
			timeout: timeout,
			allowed_updates: allowed_updates,
		};

		return callMethod!(Update[], GetUpdatesMethod)(m);
	}

	Update[] getUpdates(GetUpdatesMethod m) {
		return callMethod!(Update[], GetUpdatesMethod)(m);
	}

	auto updateGetter() {
		struct updateGetterImpl {
			private {
				TelegramBot m_bot;
				Update[] m_buffer;
				size_t m_index;
				bool m_empty;
			}

			this(TelegramBot bot) {
				m_bot = bot;
				m_buffer.reserve = 100;
				this.popFront;
			}

			auto front() { return m_buffer[m_index]; }
			bool empty() { return m_empty; }
			void popFront() {
				if(m_buffer.length > ++m_index) {
					return;
				} else {
					m_buffer = m_bot.getUpdates(m_buffer.length ? m_buffer[$-1].update_id+1 : 0);
					m_index = 0;

					if(!m_buffer.length)
						m_empty = true;
				}
			}
		}


		return updateGetterImpl(this);
	}

	bool setWebhook(string url) {
		SetWebhookMethod m = {
			url: url,
		};

		return callMethod!(bool, SetWebhookMethod)(m);
	}

	bool deleteWebhook() {
		DeleteWebhookMethod m = DeleteWebhookMethod();

		return callMethod!(bool, DeleteWebhookMethod)(m);
	}

	WebhookInfo getWebhookInfo() {
		GetWebhookInfoMethod m = GetWebhookInfoMethod();

		return callMethod!(WebhookInfo, GetWebhookInfoMethod)(m);
	}

	User getMe() {
		GetMeMethod m;

		return callMethod!(User, GetMeMethod)(m);
	}

	Message sendMessage(long chatId, string text, ParseMode pm = ParseMode.markdown) {
		SendMessageMethod m = {
			text: text,
			chat_id: chatId,
			parse_mode: pm,
		};

		return sendMessage(m);
	}

	Message sendMessage(long chatId, int reply_to, string text, ParseMode pm = ParseMode.markdown) {
		SendMessageMethod m = {
			text: text,
			chat_id: chatId,
			reply_to_message_id: reply_to,
			parse_mode: pm,
		};

		return sendMessage(m);
	}

	Message sendMessage(SendMessageMethod m) {
		return callMethod!(Message, SendMessageMethod)(m);
	}

	Message forwardMessage(long chatId, long fromChatId, uint messageId){
		ForwardMessageMethod m = {
			message_id: messageId,
			chat_id: chatId,
			from_chat_id: fromChatId,
		};

		return callMethod!(Message, ForwardMessageMethod)(m);
	}

	Message forwardMessage(ForwardMessageMethod m) {
		return callMethod!(Message, ForwardMessageMethod)(m);
	}

	Message sendPhoto(SendPhotoMethod m) {
		return callMethod!(Message, SendPhotoMethod)(m);
	}

	Message sendPhoto(long chatId, string photo) {
		SendPhotoMethod m = {
			photo: photo,
			chat_id: chatId,
		};

		return sendPhoto(m);
	}

	Message sendAudio(SendAudioMethod m) {
		return callMethod!(Message, SendAudioMethod)(m);
	}

	Message sendAudio(long chatId, string audio) {
		SendAudioMethod m = {
			audio: audio,
			chat_id: chatId,
		};

		return sendAudio(m);
	}

	Message sendDocument(SendDocumentMethod m) {
		return callMethod!(Message, SendDocumentMethod)(m);
	}

	Message sendDocument(long chatId, string document) {
		SendDocumentMethod m = {
			document: document,
			chat_id: chatId,
		};

		return sendDocument(m);
	}

	Message sendVideo(SendVideoMethod m) {
		return callMethod!(Message, SendVideoMethod)(m);
	}

	Message sendVideo(long chatId, string video) {
		SendVideoMethod m = {
			video: video,
			chat_id: chatId,
		};

		return sendVideo(m);
	}

	Message sendVoice(SendVoiceMethod m) {
		return callMethod!(Message, SendVoiceMethod)(m);
	}

	Message sendVoice(long chatId, string voice) {
		SendVoiceMethod m = {
			voice: voice,
			chat_id: chatId,
		};

		return sendVoice(m);
	}

	Message sendVideoNote(SendVideoNoteMethod m) {
		return callMethod!(Message, SendVideoNoteMethod)(m);
	}

	Message sendVideoNote(long chatId, string videoNote) {
		SendVideoNoteMethod m = {
			video_note: videoNote,
			chat_id: chatId,
		};

		return sendVideoNote(m);
	}

	Message sendMediaGroup(SendMediaGroupMethod m) {
		return callMethod!(Message, SendMediaGroupMethod)(m);
	}

	Message sendMediaGroup(long chatId, InputMedia[] media) {
		SendMediaGroupMethod m = {
			media: media,
			chat_id: chatId,
		};

		return sendMediaGroup(m);
	}

	Message sendLocation(SendLocationMethod m) {
		return callMethod!(Message, SendLocationMethod)(m);
	}

	Message sendLocation(long chatId, float latitude, float longitude) {
		SendLocationMethod m = {
			latitude: latitude,
			longitude: longitude,
			chat_id: chatId,
		};

		return sendLocation(m);
	}

	Nullable!Message editMessageLiveLocation(EditMessageLiveLocationMethod m) {
		return callMethod!(Nullable!Message, EditMessageLiveLocationMethod)(m);
	}

	Nullable!Message editMessageLiveLocation(string inlineMessageId, float latitude, float longitude) {
		EditMessageLiveLocationMethod m = {
			inline_message_id: inlineMessageId,
			latitude : latitude,
			longitude : longitude,
		};

		return editMessageLiveLocation(m);
	}

	Nullable!Message editMessageLiveLocation(long chatId, uint messageId, float latitude, float longitude) {
		EditMessageLiveLocationMethod m = {
			message_id: messageId,
			latitude: latitude,
			longitude: longitude,
			chat_id: chatId,
		};

		return editMessageLiveLocation(m);
	}

	Nullable!Message stopMessageLiveLocation(StopMessageLiveLocationMethod m) {
		return callMethod!(Nullable!Message, StopMessageLiveLocationMethod)(m);
	}

	Nullable!Message stopMessageLiveLocation(string inlineMessageId) {
		StopMessageLiveLocationMethod m = {
			inline_message_id: inlineMessageId,
		};

		return stopMessageLiveLocation(m);
	}

	Nullable!Message stopMessageLiveLocation(long chatId, uint messageId) {
		StopMessageLiveLocationMethod m = {
			message_id: messageId,
			chat_id: chatId,
		};

		return stopMessageLiveLocation(m);
	}

	Message sendVenue(SendVenueMethod m) {
		return callMethod!(Message, SendVenueMethod)(m);
	}

	Message sendVenue(long chatId, float latitude, float longitude, string title, string address) {
		SendVenueMethod m = {
			latitude: latitude,
			longitude : longitude,
			title : title,
			address : address,
			chat_id: chatId,
		};

		return sendVenue(m);
	}

	Message sendContact(SendContactMethod m) {
		return callMethod!(Message, SendContactMethod)(m);
	}

	Message sendContact(long chatId, string phone_number, string first_name) {
		SendContactMethod m = {
			phone_number: phone_number,
			first_name : first_name,
			chat_id: chatId,
		};

		return sendContact(m);
	}

	bool sendChatAction(SendChatActionMethod m) {
		return callMethod!(bool, SendChatActionMethod)(m);
	}

	bool sendChatAction(long chatId, string action) {
		SendChatActionMethod m = {
			action: action,
			chat_id: chatId,
		};

		return sendChatAction(m);
	}

	UserProfilePhotos getUserProfilePhotos(GetUserProfilePhotosMethod m) {
		return callMethod!(UserProfilePhotos, GetUserProfilePhotosMethod)(m);
	}

	UserProfilePhotos getUserProfilePhotos(int userId) {
		GetUserProfilePhotosMethod m = {
			user_id: userId,
		};

		return getUserProfilePhotos(m);
	}

	File getFile(GetFileMethod m) {
		return callMethod!(File, GetFileMethod)(m);
	}

	File getFile(string fileId) {
		GetFileMethod m = {
			file_id: fileId,
		};

		return getFile(m);
	}

	bool kickChatMember(KickChatMemberMethod m) {
		return callMethod!(bool, KickChatMemberMethod)(m);
	}

	bool kickChatMember(long chatId, int userId) {
		KickChatMemberMethod m = {
			user_id: userId,
			chat_id: chatId,
		};

		return kickChatMember(m);
	}

	bool unbanChatMember(UnbanChatMemberMethod m) {
		return callMethod!(bool, UnbanChatMemberMethod)(m);
	}

	bool unbanChatMember(long chatId, int userId) {
		UnbanChatMemberMethod m = {
			user_id: userId,
			chat_id: chatId,
		};

		return unbanChatMember(m);
	}

	bool restrictChatMember(RestrictChatMemberMethod m) {
		return callMethod!bool(m);
	}

	bool restrictChatMember(long chatId, int userId) {
		RestrictChatMemberMethod m = {
			user_id: userId,
			chat_id: chatId,
		};

		return restrictChatMember(m);
	}

	bool promoteChatMember(PromoteChatMemberMethod m) {
		return callMethod!bool(m);
	}

	bool promoteChatMember(long chatId, int userId) {
		PromoteChatMemberMethod m = {
			user_id: userId,
			chat_id: chatId,
		};

		return promoteChatMember(m);
	}

	string exportChatInviteLink(ExportChatInviteLinkMethod m) {
		return callMethod!string(m);
	}

	string exportChatInviteLink(long chatId) {
		ExportChatInviteLinkMethod m = {
			chat_id: chatId,
		};

		return exportChatInviteLink(m);
	}

	bool setChatPhoto(SetChatPhotoMethod m) {
		return callMethod!bool(m);
	}

	bool setChatPhoto(long chatId, InputFile photo) {
		SetChatPhotoMethod m = {
			photo: photo,
			chat_id: chatId,
		};

		return setChatPhoto(m);
	}

	bool deleteChatPhoto(DeleteChatPhotoMethod m) {
		return callMethod!bool(m);
	}

	bool deleteChatPhoto(long chatId) {
		DeleteChatPhotoMethod m = {
			chat_id: chatId,
		};

		return deleteChatPhoto(m);
	}

	bool setChatTitle(SetChatTitleMethod m) {
		return callMethod!bool(m);
	}

	bool setChatTitle(long chatId, string title) {
		SetChatTitleMethod m = {
			title: title,
			chat_id: chatId,
		};

		return setChatTitle(m);
	}

	bool setChatDescription(SetChatDescriptionMethod m) {
		return callMethod!bool(m);
	}

	bool setChatDescription(long chatId, string description) {
		SetChatDescriptionMethod m = {
			description: description,
			chat_id: chatId,
		};

		return setChatDescription(m);
	}

	bool pinChatMessage(PinChatMessageMethod m) {
		return callMethod!bool(m);
	}

	bool pinChatMessage(long chatId, uint messageId) {
		PinChatMessageMethod m = {
			message_id: messageId,
			chat_id: chatId,
		};

		return pinChatMessage(m);
	}

	bool unpinChatMessage(UnpinChatMessageMethod m) {
		return callMethod!bool(m);
	}

	bool unpinChatMessage(long chatId) {
		UnpinChatMessageMethod m = {
			chat_id: chatId,
		};

		return unpinChatMessage(m);
	}

	bool leaveChat(LeaveChatMethod m) {
		return callMethod!bool(m);
	}

	bool leaveChat(long chatId) {
		LeaveChatMethod m = {
			chat_id: chatId,
		};

		return leaveChat(m);
	}

	Chat getChat(GetChatMethod m) {
		return callMethod!Chat(m);
	}

	Chat getChat(long chatId) {
		GetChatMethod m = {
			chat_id: chatId,
		};

		return getChat(m);
	}

	Chat getChat(string chatId) {
		struct GetChatStringMethod {
			mixin TelegramMethod!("/getChat", HTTPMethod.GET);
			string chat_id;
		}

		GetChatStringMethod m = {
			chat_id: chatId,
		};

		return callMethod!Chat(m);
	}


	ChatMember getChatAdministrators(GetChatAdministratorsMethod m) {
		return callMethod!ChatMember(m);
	}

	ChatMember getChatAdministrators(long chatId) {
		GetChatAdministratorsMethod m = {
			chat_id: chatId,
		};

		return getChatAdministrators(m);
	}

	int getChatMembersCount(GetChatMembersCountMethod m) {
		return callMethod!int(m);
	}

	int getChatMembersCount(long chatId) {
		GetChatMembersCountMethod m = {
			chat_id: chatId,
		};

		return getChatMembersCount(m);
	}

	ChatMember getChatMember(GetChatMemberMethod m) {
		return callMethod!ChatMember(m);
	}

	ChatMember getChatMember(long chatId, int userId) {
		GetChatMemberMethod m = {
			user_id: userId,
			chat_id: chatId,
		};

		return getChatMember(m);
	}

	bool setChatStickerSet(SetChatStickerSetMethod m) {
		return callMethod!bool(m);
	}

	bool setChatStickerSet(long chatId, string stickerSetName) {
		SetChatStickerSetMethod m = {
			sticker_set_name: stickerSetName,
			chat_id: chatId,
		};

		return setChatStickerSet(m);
	}

	bool deleteChatStickerSet(DeleteChatStickerSetMethod m) {
	return callMethod!bool(m);
	}

	bool deleteChatStickerSet(long chatId) {
		DeleteChatStickerSetMethod m = {
			chat_id: chatId,
		};

		return deleteChatStickerSet(m);
	}

	bool answerCallbackQuery(AnswerCallbackQueryMethod m) {
		return callMethod!bool(m);
	}

	bool answerCallbackQuery(string callbackQueryId) {
		AnswerCallbackQueryMethod m = {
			callback_query_id: callbackQueryId,
		};

		return answerCallbackQuery(m);
	}

	bool editMessageText(EditMessageTextMethod m) {
		return callMethod!bool(m);
	}

	bool editMessageText(long chatId, int messageId, string text) {
		EditMessageTextMethod m = {
			message_id: messageId,
			text: text,
			chat_id: chatId,
		};

		return editMessageText(m);
	}

	bool editMessageText(string inlineMessageId, string text) {
		EditMessageTextMethod m = {
			inline_message_id: inlineMessageId,
			text: text,
		};

		return editMessageText(m);
	}

	bool editMessageCaption(EditMessageCaptionMethod m) {
		return callMethod!bool(m);
	}

	bool editMessageCaption(long chatId, int messageId, string caption = null) {
		EditMessageCaptionMethod m = {
			message_id: messageId,
			caption: caption,
			chat_id: chatId,
		};

		return editMessageCaption(m);
	}

	bool editMessageCaption(string inlineMessageId, string caption = null) {
		EditMessageCaptionMethod m = {
			inline_message_id: inlineMessageId,
			caption: caption,
		};

		return editMessageCaption(m);
	}

	bool editMessageReplyMarkup(EditMessageReplyMarkupMethod m) {
		return callMethod!bool(m);
	}

	bool editMessageReplyMarkup(T)(long chatId, int messageId, T replyMarkup)
	if(isReplyMarkup!T) {
		EditMessageReplyMarkupMethod m = {
			message_id: messageId,
			chat_id: chatId,
		};

		m.reply_markup = replyMarkup;

		return editMessageReplyMarkup(m);
	}

	bool editMessageReplyMarkup(string inlineMessageId, Nullable!ReplyMarkup replyMarkup) {
		EditMessageReplyMarkupMethod m = {
			inline_message_id: inlineMessageId,
			reply_markup: replyMarkup,
		};

		return editMessageReplyMarkup(m);
	}

	bool deleteMessage(DeleteMessageMethod m) {
		return callMethod!bool(m);
	}

	bool deleteMessage(long chatId, int messageId) {
		DeleteMessageMethod m = {
			message_id: messageId,
			chat_id: chatId,
		};

		return deleteMessage(m);
	}

	Message sendSticker(SendStickerMethod m) {
		return callMethod!Message(m);
	}

	// TODO sticker is InputFile|string
	Message sendSticker(long chatId, string sticker) {
		SendStickerMethod m = {
			sticker: sticker,
			chat_id: chatId,
		};

		return sendSticker(m);
	}

	StickerSet getStickerSet(GetStickerSetMethod m) {
		return callMethod!StickerSet(m);
	}

	StickerSet getStickerSet(string name) {
		GetStickerSetMethod m = {
			name: name,
		};

		return getStickerSet(m);
	}

	File uploadStickerFile(UploadStickerFileMethod m) {
		return callMethod!File(m);
	}

	File uploadStickerFile(int userId, InputFile pngSticker) {
		UploadStickerFileMethod m = {
			user_id: userId,
			png_sticker: pngSticker,
		};

		return uploadStickerFile(m);
	}

	bool createNewStickerSet(CreateNewStickerSetMethod m) {
		return callMethod!bool(m);
	}

	// TODO pngSticker is InputFile|string
	bool createNewStickerSet(int userId,
		string name,
		string title,
		string pngSticker,
		string emojis) {
			CreateNewStickerSetMethod m = {
				user_id: userId,
				name: name,
				title: title,
				png_sticker: pngSticker,
				emojis: emojis,
			};

			return createNewStickerSet(m);
	}

	bool addStickerToSet(AddStickerToSetMethod m) {
		return callMethod!bool(m);
	}

	bool addStickerToSet(int userId, string name, string pngSticker, string emojis) {
		AddStickerToSetMethod m = {
			user_id: userId,
			name : name,
			png_sticker: pngSticker,
			emojis: emojis,
		};

		return addStickerToSet(m);
	}

	bool setStickerPositionInSet(SetStickerPositionInSetMethod m) {
		return callMethod!bool(m);
	}

	bool setStickerPositionInSet(string sticker, int position) {
		SetStickerPositionInSetMethod m = {
			sticker: sticker,
			position: position,
		};

		return setStickerPositionInSet(m);
	}

	bool deleteStickerFromSet(DeleteStickerFromSetMethod m) {
		return callMethod!bool(m);
	}

	bool deleteStickerFromSet(string sticker) {
		SetStickerPositionInSetMethod m = {
			sticker: sticker,
		};

		return setStickerPositionInSet(m);
	}

	bool answerInlineQuery(AnswerInlineQueryMethod m) {
		return callMethod!bool(m);
	}

	bool answerInlineQuery(string inlineQueryId, InlineQueryResult[] results) {
		AnswerInlineQueryMethod m = {
			inline_query_id: inlineQueryId,
			results: results,
		};

		return answerInlineQuery(m);
	}
}

/******************************************************************/
/*                    Telegram types and enums                    */
/******************************************************************/

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
	Nullable!bool all_members_are_administrators;
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
	Nullable!bool can_set_sticker_set;
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
	Nullable!bool delete_chat_photo,
				  group_chat_created,
				  supergroup_chat_created,
				  channel_chat_created;
	Nullable!long migrate_to_chat_id,
				  migrate_from_chat_id;

	private @name("pinned_message") Json m_pinned_message;
	@property @ignore {
		Message pinned_message() { return m_pinned_message.deserializeJson!Message; }
		void    pinned_messagee(Message m) { m_pinned_message = m.serializeToJson; }
	}

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
	Nullable!bool resize_keyboard,
				  one_time_keyboard,
				  selective;
}

struct KeyboardButton {
	string text;
@optional:
	Nullable!bool request_contact,
				  request_location;
}

struct ReplyKeyboardRemove {
	bool remove_keyboard = true;
@optional:
	Nullable!bool selective;
}

struct InlineKeyboardMarkup {
	InlineKeyboardButton[][] inline_keyboard;
}

struct InlineKeyboardButton {
	string text;
@optional:
	Nullable!string url,
					callback_data,
					switch_inline_query,
					switch_inline_query_current_chat;
	Nullable!CallbackGame callback_game;
	Nullable!bool pay;
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
	Nullable!bool selective;
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
	Nullable!bool can_be_edited,
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


private alias InputMediaStructs = AliasSeq!(InputMediaPhoto, InputMediaVideo);
alias InputMedia = JsonableAlgebraic!InputMediaStructs;

struct InputMediaPhoto {
	string type = "photo";
	string media;
@optional:
	Nullable!string caption,
					parse_mode;
}

struct InputMediaVideo {
	string type = "video";
	string media;
@optional:
	Nullable!string caption,
					parse_mode;
	Nullable!int width,
				 height,
				 duration;
	Nullable!bool supports_streaming;
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
	Nullable!bool hide_url;
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
	Nullable!string parse_mode;
	Nullable!bool disable_web_page_preview;
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
}

struct InputContactMessageContent {
	string phone_number;
	string first_name;
@optional:
	Nullable!string last_name;
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

mixin template TelegramMethod(string path, HTTPMethod method = HTTPMethod.POST) {
package:
	immutable string _path = path;
	HTTPMethod _httpMethod = method;
}

/// UDA for telegram methods
struct Method {
	string path;
}

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
	mixin TelegramMethod!("/getWebhookInfo", HTTPMethod.GET);
}

struct GetMeMethod {
	mixin TelegramMethod!("/getMe", HTTPMethod.GET);
}

struct SendMessageMethod {
	mixin TelegramMethod!"/sendMessage";

	long chat_id;
	string text;
	ParseMode parse_mode;
	bool disable_web_page_preview;
	bool disable_notification;
	int reply_to_message_id;

	ReplyMarkup reply_markup;
}

struct ForwardMessageMethod {
	mixin TelegramMethod!"/forwardMessage";

	long chat_id;
	long from_chat_id;
	bool disable_notification;
	int message_id;
}

struct SendPhotoMethod {
	mixin TelegramMethod!"/sendPhoto";

	long chat_id;
	string photo;
	string caption;
	ParseMode parse_mode;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendAudioMethod {
	mixin TelegramMethod!"/sendAudio";

	long chat_id;
	string audio;
	string caption;
	ParseMode parse_mode;
	int duration;
	string performer;
	string title;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;

}

struct SendDocumentMethod {
	mixin TelegramMethod!"/sendDocument";

	long chat_id;
	string document;
	string caption;
	ParseMode parse_mode;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendVideoMethod {
	mixin TelegramMethod!"/sendVideo";

	long chat_id;
	string video;
	int duration;
	int width;
	int height;
	string caption;
	ParseMode parse_mode;
	bool supports_streaming;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendVoiceMethod {
	mixin TelegramMethod!"/sendVoice";

	long chat_id;
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

	long chat_id;
	string video_note;
	int duration;
	int length;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;

}

struct SendMediaGroupMethod {
	mixin TelegramMethod!"/sendMediaGroup";

	long chat_id;
	InputMedia[] media;
	bool disable_notification;
	int reply_to_message_id;
}

struct SendLocationMethod {
	mixin TelegramMethod!"/sendLocation";

	long chat_id;
	float latitude;
	float longitude;
	int live_period;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct EditMessageLiveLocationMethod {
	mixin TelegramMethod!"/editMessageLiveLocation";

	long chat_id;
	int message_id;
	string inline_message_id;
	float latitude;
	float longitude;
	ReplyMarkup reply_markup;
}

struct StopMessageLiveLocationMethod {
	mixin TelegramMethod!"/stopMessageLiveLocation";

	long chat_id;
	int message_id;
	string inline_message_id;
	ReplyMarkup reply_markup;
}

struct SendVenueMethod {
	mixin TelegramMethod!"/sendVenue";

	long chat_id;
	float latitude;
	float longitude;
	string title;
	string address;
	string foursquare_id;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendContactMethod {
	mixin TelegramMethod!"/sendContact";

	long chat_id;
	string phone_number;
	string first_name;
	string last_name;
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct SendChatActionMethod {
	mixin TelegramMethod!"/sendChatAction";

	long chat_id;
	string action; // TODO enum
}

struct GetUserProfilePhotosMethod {
	mixin TelegramMethod!("/getUserProfilePhotos", HTTPMethod.GET);

	int user_id;
	int offset;
	int limit;
}

struct GetFileMethod {
	mixin TelegramMethod!("/getFile", HTTPMethod.GET);

	string file_id;
}

struct KickChatMemberMethod {
	mixin TelegramMethod!"/kickChatMember";

	long chat_id;
	int user_id;
	int until_date;
}

struct UnbanChatMemberMethod {
	mixin TelegramMethod!"/unbanChatMember";

	long chat_id;
	int user_id;
}

struct RestrictChatMemberMethod {
	mixin TelegramMethod!"/restrictChatMember";

	long chat_id;
	int user_id;
	int until_date;
	bool can_send_messages;
	bool can_send_media_messages;
	bool can_send_other_messages;
	bool can_add_web_page_previews;
}

struct PromoteChatMemberMethod {
	mixin TelegramMethod!"/promoteChatMember";

	long chat_id;
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

	long chat_id;
}

struct SetChatPhotoMethod {
	mixin TelegramMethod!"/setChatPhoto";

	long chat_id;
	InputFile photo;

}

struct DeleteChatPhotoMethod {
	mixin TelegramMethod!"/deleteChatPhoto";

	long chat_id;
}

struct SetChatTitleMethod {
	mixin TelegramMethod!"/setChatTitle";

	long chat_id;
	string title;
}

struct SetChatDescriptionMethod {
	mixin TelegramMethod!"/setChatDescription";

	long chat_id;
	string description;
}

struct PinChatMessageMethod {
	mixin TelegramMethod!"/pinChatMessage";

	long chat_id;
	int message_id;
	bool disable_notification;
}

struct UnpinChatMessageMethod {
	mixin TelegramMethod!"/unpinChatMessage";

	long chat_id;
}

struct LeaveChatMethod {
	mixin TelegramMethod!"/leaveChat";

	long chat_id;
}

struct GetChatMethod {
	mixin TelegramMethod!("/getChat", HTTPMethod.GET);

	long chat_id;
}

struct GetChatAdministratorsMethod {
	mixin TelegramMethod!("/getChatAdministrators", HTTPMethod.GET);

	long chat_id;
}

struct GetChatMembersCountMethod {
	mixin TelegramMethod!("/getChatMembersCount", HTTPMethod.GET);

	long chat_id;
}

struct GetChatMemberMethod {
	mixin TelegramMethod!("/getChatMember", HTTPMethod.GET);

	long chat_id;
	int user_id;
}

struct SetChatStickerSetMethod {
	mixin TelegramMethod!"/setChatStickerSet";

	long chat_id;
	string sticker_set_name;
}

struct DeleteChatStickerSetMethod {
	mixin TelegramMethod!"/deleteChatStickerSet";

	long chat_id;
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
	mixin TelegramMethod!"/editMessageTextMethod";

	long chat_id;
	int message_id;
	string inline_message_id;
	string text;
	ParseMode parse_mode;
	bool disable_web_page_preview;
	ReplyMarkup reply_markup;
}

struct EditMessageCaptionMethod {
	mixin TelegramMethod!"/editMessageCaptionMethod";

	long chat_id;
	int message_id;
	string inline_message_id;
	string caption;
	ParseMode parse_mode;
	ReplyMarkup reply_markup;
}

struct EditMessageReplyMarkupMethod {
	mixin TelegramMethod!"/editMessageReplyMarkupMethod";

	long chat_id;
	int message_id;
	string inline_message_id;
	ReplyMarkup reply_markup;
}

struct DeleteMessageMethod {
	mixin TelegramMethod!"/deleteMessageMethod";

	long chat_id;
	int message_id;
}

struct SendStickerMethod {
	mixin TelegramMethod!"/sendStickerMethod";

	long chat_id;
	string sticker; // TODO InputFile|string
	bool disable_notification;
	int reply_to_message_id;
	ReplyMarkup reply_markup;
}

struct GetStickerSetMethod {
	mixin TelegramMethod!("/getStickerSetMethod", HTTPMethod.GET);

	string name;
}

struct UploadStickerFileMethod {
	mixin TelegramMethod!"/uploadStickerFileMethod";

	int user_id;
	InputFile png_sticker;
}

struct CreateNewStickerSetMethod {
	mixin TelegramMethod!"/createNewStickerSetMethod";

	int user_id;
	string name;
	string title;
	string png_sticker; // TODO InputFile|string
	string emojis;
	bool contains_masks;
	MaskPosition mask_position;
}

struct AddStickerToSetMethod {
	mixin TelegramMethod!"/addStickerToSetMethod";

	int user_id;
	string name;
	string png_sticker; // TODO InputFile|string
	string emojis;
	MaskPosition mask_position;
}

struct SetStickerPositionInSetMethod {
	mixin TelegramMethod!"/setStickerPositionInSetMethod";

	string sticker;
	int position;
}

struct DeleteStickerFromSetMethod {
	mixin TelegramMethod!"/deleteStickerFromSetMethod";

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

private struct JsonableAlgebraic(Typelist...) {
	import std.meta;
	import std.variant;
	import vibe.data.json : Json;

	private Algebraic!Typelist types;

	// TODO implement copy constructor from Typelist types

	void opAssign(T)(T value) if(staticIndexOf!(T, Typelist) >= 0) {
		types = value;
	}

	@safe Json toJson() const {
		if(!types.hasValue) {
			return Json.emptyObject;
		}

		return getJson();
	}

	// this method should not be used
	@safe typeof(this) fromJson(Json src) {
		return typeof(this).init;
	}

	@trusted protected Json getJson() const {
		import vibe.data.json : serializeToJson;

		static foreach (T; Typelist) {
			if(types.type == typeid(T)) {
				T reply = cast(T) types.get!T;

				return reply.serializeToJson();
			}
		}

		return Json(null);
	}
}

unittest {
	import vibe.data.json;

	struct S1 {
		int s1;
	}

	struct S2 {
		string s2;
	}

	JsonableAlgebraic!(S1, S2) jsonable;

	struct JsonableAggregate {
		JsonableAlgebraic!(S1, S2) aggr;
	}

	jsonable = S1(42);
	assert(`{"s1":42}` == jsonable.serializeToJsonString());

	jsonable = S2("s2 value");
	assert(`{"s2":"s2 value"}` == jsonable.serializeToJsonString());

	JsonableAggregate jaggr;
	jaggr.aggr = jsonable;
	assert(`{"aggr":{"s2":"s2 value"}}` == jaggr.serializeToJsonString());
}
