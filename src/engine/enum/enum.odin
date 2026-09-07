package engine_enums

AccessModifierType :: enum {
	Allow = 0,
	Deny = 1,
}

AccessoryType :: enum {
	Unknown = 0,
	Hat = 1,
	Hair = 2,
	Face = 3,
	Neck = 4,
	Shoulder = 5,
	Front = 6,
	Back = 7,
	Waist = 8,
	TShirt = 9,
	Shirt = 10,
	Pants = 11,
	Jacket = 12,
	Sweater = 13,
	Shorts = 14,
	LeftShoe = 15,
	RightShoe = 16,
	DressSkirt = 17,
	Eyebrow = 18,
	Eyelash = 19,
}

ActionOnAutoResumeSync :: enum {
	DontResume = 0,
	KeepStudio = 1,
	KeepLocal = 2,
}

ActionOnStopSync :: enum {
	AlwaysAsk = 0,
	KeepLocalFiles = 1,
	DeleteLocalFiles = 2,
}

ActionType :: enum {
	Nothing = 0,
	Pause = 1,
	Lose = 2,
	Draw = 3,
	Win = 4,
}

ActuatorRelativeTo :: enum {
	Attachment0 = 0,
	Attachment1 = 1,
	World = 2,
}

ActuatorType :: enum {
	None = 0,
	Motor = 1,
	Servo = 2,
}

AdAvailabilityResult :: enum {
	IsAvailable = 1,
	DeviceIneligible = 2,
	ExperienceIneligible = 3,
	InternalError = 4,
	NoFill = 5,
	PlayerIneligible = 6,
	PublisherIneligible = 7,
}

AdEventType :: enum {
	RewardedAdLoaded = 3,
	RewardedAdGrant = 4,
	RewardedAdUnloaded = 5,
	VideoLoaded = 0,
	VideoRemoved = 1,
	UserCompletedVideo = 2,
}

AdFormat :: enum {
	RewardedVideo = 0,
}

AdShape :: enum {
	HorizontalRectangle = 1,
}

AdTeleportMethod :: enum {
	Undefined = 0,
	PortalForward = 1,
	InGameMenuBackButton = 2,
	UIBackButton = 3,
}

AdUIEventType :: enum {
	AdLabelClicked = 0,
	VolumeButtonClicked = 1,
	FullscreenButtonClicked = 2,
	PlayButtonClicked = 3,
	PauseButtonClicked = 4,
	CloseButtonClicked = 5,
	WhyThisAdClicked = 6,
	PlayEventTriggered = 7,
	PauseEventTriggered = 8,
}

AdUIType :: enum {
	None = 0,
	Image = 1,
	Video = 2,
}

AdUnitStatus :: enum {
	Inactive = 0,
	Active = 1,
}

AdornCullingMode :: enum {
	Automatic = 0,
	Never = 1,
}

AdornShading :: enum {
	Default = 0,
	Shaded = 1,
	XRay = 2,
	XRayShaded = 3,
	AlwaysOnTop = 4,
}

AlignType :: enum {
	PrimaryAxisParallel = 2,
	PrimaryAxisPerpendicular = 3,
	PrimaryAxisLookAt = 4,
	AllAxes = 5,
	Parallel = 0,
	Perpendicular = 1,
}

AlphaMode :: enum {
	Overlay = 0,
	Transparency = 1,
	TintMask = 2,
	Opaque = 3,
}

AnalyticsCustomFieldKeys :: enum {
	CustomField01 = 0,
	CustomField02 = 1,
	CustomField03 = 2,
}

AnalyticsEconomyAction :: enum {
	Default = 0,
	Acquire = 1,
	Spend = 2,
}

AnalyticsEconomyFlowType :: enum {
	Sink = 0,
	Source = 1,
}

AnalyticsEconomyTransactionType :: enum {
	IAP = 0,
	Shop = 1,
	Gameplay = 2,
	ContextualPurchase = 3,
	TimedReward = 4,
	Onboarding = 5,
}

AnalyticsLogLevel :: enum {
	Trace = 0,
	Debug = 1,
	Information = 2,
	Warning = 3,
	Error = 4,
	Fatal = 5,
}

AnalyticsProgressionStatus :: enum {
	Default = 0,
	Begin = 1,
	Complete = 2,
	Abandon = 3,
	Fail = 4,
}

AnalyticsProgressionType :: enum {
	Custom = 0,
	Start = 1,
	Fail = 2,
	Complete = 3,
}

AnimationClipFromVideoStatus :: enum {
	Initializing = 0,
	Pending = 1,
	Processing = 2,
	ErrorGeneric = 4,
	Success = 6,
	ErrorVideoTooLong = 7,
	ErrorNoPersonDetected = 8,
	ErrorVideoUnstable = 9,
	Timeout = 10,
	Cancelled = 11,
	ErrorMultiplePeople = 12,
	ErrorUploadingVideo = 2001,
}

AnimationNodeBlend2DInputMode :: enum {
	Cartesian = 0,
	Polar = 1,
}

AnimationNodeInterruptible :: enum {
	Always = 0,
	ClipFinished = 1,
	Expression = 2,
}

AnimationNodePlayMode :: enum {
	Loop = 0,
	PingPong = 1,
	OnceAndHold = 2,
	OnceAndReset = 3,
}

AnimationNodeTransitionType :: enum {
	CrossFade = 0,
	InertialBlend = 1,
	DeadBlend = 2,
}

AnimationNodeType :: enum {
	InvalidNode = 0,
	AddNode = 1,
	BlendNode = 2,
	Blend1DNode = 3,
	Blend2DNode = 4,
	ClipNode = 5,
	GraphOutput = 6,
	MaskNode = 7,
	PrioritySelectNode = 8,
	RandomSequenceNode = 9,
	SelectNode = 10,
	SequenceNode = 11,
	SpeedNode = 12,
	SubtractNode = 13,
}

AnimationNodeWaitFor :: enum {
	ClipFinished = 0,
	Expression = 1,
}

AnimationPriority :: enum {
	Core = 1000,
	Idle = 0,
	Movement = 1,
	Action = 2,
	Action2 = 3,
	Action3 = 4,
	Action4 = 5,
}

AnimatorRetargetingMode :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

AnnotationChannelContentPreference :: enum {
	None = 0,
	All = 1,
	Unknown = 2,
}

AnnotationEditingMode :: enum {
	None = 0,
	PlacingNew = 1,
	WritingNew = 2,
}

AnnotationPlaceContentPreference :: enum {
	None = 0,
	All = 1,
	MentionsAndReplies = 2,
	Unknown = 3,
}

AnnotationRequestStatus :: enum {
	Success = 0,
	Loading = 1,
	ErrorInternalFailure = 2,
	ErrorNotFound = 3,
	ErrorModerated = 4,
}

AnnotationRequestType :: enum {
	Unknown = 0,
	Create = 1,
	Resolve = 2,
	Delete = 3,
	Edit = 4,
}

AppLifecycleManagerState :: enum {
	Detached = 0,
	Active = 1,
	Inactive = 2,
	Hidden = 3,
}

AppShellActionType :: enum {
	None = 0,
	OpenApp = 1,
	TapChatTab = 2,
	TapConversationEntry = 3,
	TapAvatarTab = 4,
	ReadConversation = 5,
	TapGamePageTab = 6,
	TapHomePageTab = 7,
	GamePageLoaded = 8,
	HomePageLoaded = 9,
	AvatarEditorPageLoaded = 10,
}

AppShellFeature :: enum {
	None = 0,
	Chat = 1,
	AvatarEditor = 2,
	GamePage = 3,
	HomePage = 4,
	More = 5,
	Landing = 6,
}

AppUpdateStatus :: enum {
	Unknown = 0,
	NotSupported = 1,
	Failed = 2,
	NotAvailable = 3,
	Available = 4,
	AvailableBoundChannel = 5,
	AvailableBetaProgram = 6,
}

ApplyStrokeMode :: enum {
	Contextual = 0,
	Border = 1,
}

AspectType :: enum {
	FitWithinMaxSize = 0,
	ScaleWithParentSize = 1,
}

AssetCreatorType :: enum {
	User = 0,
	Group = 1,
}

AssetFetchStatus :: enum {
	Success = 0,
	Failure = 1,
	None = 2,
	Loading = 3,
	TimedOut = 4,
}

AssetType :: enum {
	Image = 1,
	TShirt = 2,
	Audio = 3,
	Mesh = 4,
	Lua = 5,
	Hat = 8,
	Place = 9,
	Model = 10,
	Shirt = 11,
	Pants = 12,
	Decal = 13,
	Head = 17,
	Face = 18,
	Gear = 19,
	Badge = 21,
	Animation = 24,
	Torso = 27,
	RightArm = 28,
	LeftArm = 29,
	LeftLeg = 30,
	RightLeg = 31,
	Package = 32,
	GamePass = 34,
	Plugin = 38,
	MeshPart = 40,
	HairAccessory = 41,
	FaceAccessory = 42,
	NeckAccessory = 43,
	ShoulderAccessory = 44,
	FrontAccessory = 45,
	BackAccessory = 46,
	WaistAccessory = 47,
	ClimbAnimation = 48,
	DeathAnimation = 49,
	FallAnimation = 50,
	IdleAnimation = 51,
	JumpAnimation = 52,
	RunAnimation = 53,
	SwimAnimation = 54,
	WalkAnimation = 55,
	PoseAnimation = 56,
	EmoteAnimation = 61,
	Video = 62,
	TShirtAccessory = 64,
	ShirtAccessory = 65,
	PantsAccessory = 66,
	JacketAccessory = 67,
	SweaterAccessory = 68,
	ShortsAccessory = 69,
	LeftShoeAccessory = 70,
	RightShoeAccessory = 71,
	DressSkirtAccessory = 72,
	FontFamily = 73,
	EyebrowAccessory = 76,
	EyelashAccessory = 77,
	MoodAnimation = 78,
	DynamicHead = 79,
	FaceMakeup = 88,
	LipMakeup = 89,
	EyeMakeup = 90,
	EarAccessory = 57,
	EyeAccessory = 58,
}

AssetTypeVerification :: enum {
	Default = 1,
	ClientOnly = 2,
	Always = 3,
}

AudioApiRollout :: enum {
	Disabled = 0,
	Automatic = 1,
	Enabled = 2,
}

AudioChannelLayout :: enum {
	Mono = 0,
	Stereo = 1,
	Quad = 2,
	Surround_5 = 3,
	Surround_5_1 = 4,
	Surround_7_1 = 5,
	Surround_7_1_4 = 6,
}

AudioFilterType :: enum {
	Peak = 0,
	LowShelf = 1,
	HighShelf = 2,
	Lowpass12dB = 3,
	Lowpass24dB = 4,
	Lowpass48dB = 5,
	Highpass12dB = 6,
	Highpass24dB = 7,
	Highpass48dB = 8,
	Bandpass = 9,
	Notch = 10,
	Lowpass6dB = 11,
}

AudioSimulationFidelity :: enum {
	None = 0,
	Automatic = 1,
}

AudioSubType :: enum {
	Music = 1,
	SoundEffect = 2,
}

AudioWindowSize :: enum {
	Small = 0,
	Medium = 1,
	Large = 2,
}

AuthorityMode :: enum {
	Server = 0,
	Automatic = 1,
}

AutoIndentRule :: enum {
	Off = 0,
	Absolute = 1,
	Relative = 2,
}

AutomaticSize :: enum {
	None = 0,
	X = 1,
	Y = 2,
	XY = 3,
}

AvatarAssetType :: enum {
	TShirt = 2,
	Hat = 8,
	Shirt = 11,
	Pants = 12,
	Head = 17,
	Face = 18,
	Gear = 19,
	Torso = 27,
	RightArm = 28,
	LeftArm = 29,
	LeftLeg = 30,
	RightLeg = 31,
	HairAccessory = 41,
	FaceAccessory = 42,
	NeckAccessory = 43,
	ShoulderAccessory = 44,
	FrontAccessory = 45,
	BackAccessory = 46,
	WaistAccessory = 47,
	ClimbAnimation = 48,
	FallAnimation = 50,
	IdleAnimation = 51,
	JumpAnimation = 52,
	RunAnimation = 53,
	SwimAnimation = 54,
	WalkAnimation = 55,
	MoodAnimation = 78,
	EmoteAnimation = 61,
	TShirtAccessory = 64,
	ShirtAccessory = 65,
	PantsAccessory = 66,
	JacketAccessory = 67,
	SweaterAccessory = 68,
	ShortsAccessory = 69,
	LeftShoeAccessory = 70,
	RightShoeAccessory = 71,
	DressSkirtAccessory = 72,
	EyebrowAccessory = 76,
	EyelashAccessory = 77,
	DynamicHead = 79,
	FaceMakeup = 88,
	LipMakeup = 89,
	EyeMakeup = 90,
}

AvatarChatServiceFeature :: enum {
	None = 0,
	UniverseAudio = 1,
	UniverseVideo = 2,
	PlaceAudio = 4,
	PlaceVideo = 8,
	UserAudioEligible = 16,
	UserAudio = 32,
	UserVideoEligible = 64,
	UserVideo = 128,
	UserBanned = 256,
	UserVerifiedForVoice = 512,
}

AvatarContextMenuOption :: enum {
	Friend = 0,
	Chat = 1,
	Emote = 2,
	InspectMenu = 3,
}

AvatarGenerationError :: enum {
	None = 0,
	Unknown = 1,
	DownloadFailed = 2,
	Canceled = 3,
	Offensive = 4,
	Timeout = 5,
	JobNotFound = 6,
}

AvatarItemType :: enum {
	Asset = 1,
	Bundle = 2,
}

AvatarPromptResult :: enum {
	Success = 1,
	PermissionDenied = 2,
	Failed = 3,
}

AvatarSettingsAccessoryLimitMethod :: enum {
	Scale = 0,
	Remove = 1,
	PreviewScale = 2,
	PreviewRemove = 3,
}

AvatarSettingsAccessoryMode :: enum {
	PlayerChoice = 0,
	CustomLimit = 1,
}

AvatarSettingsAnimationClipsMode :: enum {
	PlayerChoice = 0,
	CustomClips = 1,
}

AvatarSettingsAnimationPacksMode :: enum {
	PlayerChoice = 0,
	StandardR15 = 1,
	StandardR6 = 2,
}

AvatarSettingsAppearanceMode :: enum {
	PlayerChoice = 0,
	CustomParts = 1,
	CustomBody = 2,
}

AvatarSettingsBuildMode :: enum {
	PlayerChoice = 0,
	CustomBuild = 1,
}

AvatarSettingsClothingMode :: enum {
	PlayerChoice = 0,
	CustomLimit = 1,
}

AvatarSettingsCollisionMode :: enum {
	Default = 0,
	SingleCollider = 1,
	Legacy = 2,
}

AvatarSettingsCustomAccessoryMode :: enum {
	PlayerChoice = 0,
	CustomAccessories = 1,
}

AvatarSettingsCustomBodyType :: enum {
	AvatarReference = 0,
	BundleId = 1,
}

AvatarSettingsCustomClothingMode :: enum {
	PlayerChoice = 0,
	CustomClothing = 1,
}

AvatarSettingsHitAndTouchDetectionMode :: enum {
	UseParts = 0,
	UseCollider = 1,
}

AvatarSettingsJumpMode :: enum {
	JumpHeight = 0,
	JumpPower = 1,
}

AvatarSettingsLegacyCollisionMode :: enum {
	R6Colliders = 0,
	InnerBoxColliders = 1,
}

AvatarSettingsScaleMode :: enum {
	PlayerChoice = 0,
	CustomScale = 1,
}

AvatarThumbnailCustomizationType :: enum {
	Closeup = 1,
	FullBody = 2,
}

AvatarUnificationMode :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

Axis :: enum {
	X = 0,
	Y = 1,
	Z = 2,
}

BenefitType :: enum {
	DeveloperProduct = 0,
	AvatarAsset = 1,
	AvatarBundle = 2,
}

BinType :: enum {
	Script = 0,
	GameTool = 1,
	Grab = 2,
	Clone = 3,
	Hammer = 4,
}

BodyPart :: enum {
	Head = 0,
	Torso = 1,
	LeftArm = 2,
	RightArm = 3,
	LeftLeg = 4,
	RightLeg = 5,
}

BodyPartR15 :: enum {
	Head = 0,
	UpperTorso = 1,
	LowerTorso = 2,
	LeftFoot = 3,
	LeftLowerLeg = 4,
	LeftUpperLeg = 5,
	RightFoot = 6,
	RightLowerLeg = 7,
	RightUpperLeg = 8,
	LeftHand = 9,
	LeftLowerArm = 10,
	LeftUpperArm = 11,
	RightHand = 12,
	RightLowerArm = 13,
	RightUpperArm = 14,
	RootPart = 15,
	Unknown = 17,
}

BorderMode :: enum {
	Outline = 0,
	Middle = 1,
	Inset = 2,
}

BorderStrokePosition :: enum {
	Outer = 0,
	Center = 1,
	Inner = 2,
}

BreakReason :: enum {
	Other = 0,
	Error = 1,
	SpecialBreakpoint = 2,
	UserBreakpoint = 3,
}

BreakpointRemoveReason :: enum {
	Requested = 0,
	ScriptChanged = 1,
	ScriptRemoved = 2,
}

BulkMoveMode :: enum {
	FireAllEvents = 0,
	FireCFrameChanged = 1,
}

BundleType :: enum {
	BodyParts = 1,
	Animations = 2,
	Shoes = 3,
	DynamicHead = 4,
	DynamicHeadAvatar = 5,
}

Button :: enum {
	Jump = 32,
	Dismount = 8,
}

CageType :: enum {
	Inner = 0,
	Outer = 1,
}

CameraMode :: enum {
	Classic = 0,
	LockFirstPerson = 1,
}

CameraPanMode :: enum {
	Classic = 0,
	EdgeBump = 1,
}

CameraSpeedAdjustBinding :: enum {
	None = 0,
	RmbScroll = 1,
	AltScroll = 2,
}

CameraType :: enum {
	Fixed = 0,
	Attach = 1,
	Watch = 2,
	Track = 3,
	Follow = 4,
	Custom = 5,
	Scriptable = 6,
	Orbital = 7,
}

CaptureGalleryPermission :: enum {
	ReadAndUpload = 0,
}

CaptureType :: enum {
	Screenshot = 1,
	Video = 2,
}

CellBlock :: enum {
	Solid = 0,
	VerticalWedge = 1,
	CornerWedge = 2,
	InverseCornerWedge = 3,
	HorizontalWedge = 4,
}

CellMaterial :: enum {
	Empty = 0,
	Grass = 1,
	Sand = 2,
	Brick = 3,
	Granite = 4,
	Asphalt = 5,
	Iron = 6,
	Aluminum = 7,
	Gold = 8,
	WoodPlank = 9,
	WoodLog = 10,
	Gravel = 11,
	CinderBlock = 12,
	MossyStone = 13,
	Cement = 14,
	RedPlastic = 15,
	BluePlastic = 16,
	Water = 17,
}

CellOrientation :: enum {
	NegZ = 0,
	X = 1,
	Z = 2,
	NegX = 3,
}

CenterDialogType :: enum {
	UnsolicitedDialog = 1,
	PlayerInitiatedDialog = 2,
	ModalDialog = 3,
	QuitDialog = 4,
}

CharacterControlMode :: enum {
	Default = 0,
	Legacy = 1,
	NoCharacterController = 2,
	LuaCharacterController = 3,
}

ChatCallbackType :: enum {
	OnCreatingChatWindow = 1,
	OnClientSendingMessage = 2,
	OnClientFormattingMessage = 3,
	OnServerReceivingMessage = 17,
}

ChatColor :: enum {
	Blue = 0,
	Green = 1,
	Red = 2,
	White = 3,
}

ChatMode :: enum {
	Menu = 0,
	TextAndMenu = 1,
}

ChatPrivacyMode :: enum {
	AllUsers = 0,
	NoOne = 1,
	Friends = 2,
}

ChatRestrictionStatus :: enum {
	Unknown = 0,
	NotRestricted = 1,
	Restricted = 2,
}

ChatStyle :: enum {
	Classic = 0,
	Bubble = 1,
	ClassicAndBubble = 2,
}

ChatVersion :: enum {
	LegacyChatService = 0,
	TextChatService = 1,
}

ClientAnimatorThrottlingMode :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

CloseReason :: enum {
	Unknown = 0,
	DeveloperShutdown = 2,
	DeveloperUpdate = 3,
	ServerEmpty = 4,
	OutOfMemory = 5,
}

CollaboratorStatus :: enum {
	None = 0,
	Editing3D = 1,
	Scripting = 2,
	PrivateScripting = 3,
}

CollisionFidelity :: enum {
	Default = 0,
	Hull = 1,
	Box = 2,
	PreciseConvexDecomposition = 3,
}

CommandPermission :: enum {
	Plugin = 0,
	LocalUser = 1,
}

CompileTarget :: enum {
	Client = 0,
	CoreScript = 1,
	Studio = 2,
	CoreScriptRaw = 3,
}

CompletionAcceptanceBehavior :: enum {
	Insert = 0,
	Replace = 1,
	ReplaceOnEnterInsertOnTab = 2,
	InsertOnEnterReplaceOnTab = 3,
}

CompletionItemKind :: enum {
	Text = 1,
	Method = 2,
	Function = 3,
	Constructor = 4,
	Field = 5,
	Variable = 6,
	Class = 7,
	Interface = 8,
	Module = 9,
	Property = 10,
	Unit = 11,
	Value = 12,
	Enum = 13,
	Keyword = 14,
	Snippet = 15,
	Color = 16,
	File = 17,
	Reference = 18,
	Folder = 19,
	EnumMember = 20,
	Constant = 21,
	Struct = 22,
	Event = 23,
	Operator = 24,
	TypeParameter = 25,
}

CompletionItemTag :: enum {
	Deprecated = 1,
	IncorrectIndexType = 2,
	PluginPermissions = 3,
	CommandLinePermissions = 4,
	AddParens = 6,
	PutCursorInParens = 7,
	TypeCorrect = 8,
	ClientServerBoundaryViolation = 9,
	Invalidated = 10,
	PutCursorBeforeEnd = 11,
}

CompletionTriggerKind :: enum {
	Invoked = 1,
	TriggerCharacter = 2,
	TriggerForIncompleteCompletions = 3,
}

CompositeValueCurveType :: enum {
	ColorRGB = 0,
	ColorHSV = 1,
	NumberRange = 2,
	Rect = 3,
	UDim = 4,
	UDim2 = 5,
	Vector2 = 6,
	Vector3 = 7,
}

CompressionAlgorithm :: enum {
	Zstd = 0,
	Zlib = 1,
	lz4 = 3,
	flate = 4,
	brotli = 5,
}

ComputerCameraMovementMode :: enum {
	Default = 0,
	Classic = 1,
	Follow = 2,
	Orbital = 3,
	CameraToggle = 4,
}

ComputerMovementMode :: enum {
	Default = 0,
	KeyboardMouse = 1,
	ClickToMove = 2,
}

ConfigSnapshotErrorState :: enum {
	None = 0,
	LoadFailed = 1,
}

ConnectionError :: enum {
	OK = 0,
	Unknown = 1,
	ConnectErrors = 2,
	AlreadyConnected = 3,
	NoFreeIncomingConnections = 4,
	ConnectionBanned = 5,
	InvalidPassword = 6,
	IncompatibleProtocolVersion = 7,
	IPRecentlyConnected = 8,
	OurSystemRequiresSecurity = 9,
	SecurityKeyMismatch = 10,
	DisconnectErrors = 256,
	DisconnectBadhash = 257,
	DisconnectSecurityKeyMismatch = 258,
	DisconnectProtocolMismatch = 259,
	DisconnectReceivePacketError = 260,
	DisconnectReceivePacketStreamError = 261,
	DisconnectSendPacketError = 262,
	DisconnectIllegalTeleport = 263,
	DisconnectDuplicatePlayer = 264,
	DisconnectDuplicateTicket = 265,
	DisconnectTimeout = 266,
	DisconnectLuaKick = 267,
	DisconnectOnRemoteSysStats = 268,
	DisconnectHashTimeout = 269,
	DisconnectCloudEditKick = 270,
	DisconnectPlayerless = 271,
	DisconnectNewSecurityKeyMismatch = 272,
	DisconnectEvicted = 273,
	DisconnectDevMaintenance = 274,
	DisconnectRejoin = 276,
	DisconnectConnectionLost = 277,
	DisconnectIdle = 278,
	DisconnectRaknetErrors = 279,
	DisconnectWrongVersion = 280,
	DisconnectBySecurityPolicy = 281,
	DisconnectBlockedIP = 282,
	DisconnectClientFailure = 284,
	DisconnectClientRequest = 285,
	DisconnectPrivateServerKickout = 286,
	DisconnectModeratedGame = 287,
	ServerShutdown = 288,
	ReplicatorTimeout = 290,
	PlayerRemoved = 291,
	DisconnectOutOfMemoryKeepPlayingLeave = 292,
	DisconnectRomarkEndOfTest = 293,
	DisconnectCollaboratorPermissionRevoked = 294,
	DisconnectCollaboratorUnderage = 295,
	NetworkInternal = 296,
	NetworkSend = 297,
	NetworkTimeout = 298,
	NetworkMisbehavior = 299,
	NetworkSecurity = 300,
	ReplacementReady = 301,
	ServerEmpty = 302,
	PhantomFreeze = 303,
	AndroidAnticheatKick = 304,
	AndroidEmulatorKick = 305,
	AndroidRootedKick = 306,
	ScreentimeLockoutKick = 307,
	DisconnectionNotification = 308,
	DisconnectVerboselyModeratedGame = 309,
	PlacelaunchErrors = 512,
	PlacelaunchDisabled = 515,
	PlacelaunchError = 516,
	PlacelaunchGameEnded = 517,
	PlacelaunchGameFull = 518,
	PlacelaunchUserLeft = 522,
	PlacelaunchRestricted = 523,
	PlacelaunchUnauthorized = 524,
	PlacelaunchFlooded = 525,
	PlacelaunchHashExpired = 526,
	PlacelaunchHashException = 527,
	PlacelaunchPartyCannotFit = 528,
	PlacelaunchHttpError = 529,
	PlacelaunchUserPrivacyUnauthorized = 533,
	PlacelaunchCreatorBan = 600,
	PlacelaunchCustomMessage = 610,
	PlacelaunchOtherError = 611,
	TeleportErrors = 768,
	TeleportFailure = 769,
	TeleportGameNotFound = 770,
	TeleportGameEnded = 771,
	TeleportGameFull = 772,
	TeleportUnauthorized = 773,
	TeleportFlooded = 774,
	TeleportIsTeleporting = 775,
}

ConnectionState :: enum {
	Connected = 0,
	Disconnected = 1,
}

ContentSourceType :: enum {
	None = 0,
	Uri = 1,
	Object = 2,
	Opaque = 3,
}

ContextActionPriority :: enum {
	Low = 1000,
	Medium = 2000,
	High = 3000,
}

ContextActionResult :: enum {
	Sink = 0,
	Pass = 1,
}

ControlMode :: enum {
	Classic = 0,
	MouseLockSwitch = 1,
}

CoreGuiType :: enum {
	PlayerList = 0,
	Health = 1,
	Backpack = 2,
	Chat = 3,
	All = 4,
	EmotesMenu = 5,
	SelfView = 6,
}

CreateAssetResult :: enum {
	Success = 1,
	PermissionDenied = 2,
	UploadFailed = 3,
	Unknown = 4,
}

CreateOutfitFailure :: enum {
	InvalidName = 1,
	OutfitLimitReached = 2,
	Other = 3,
}

CreatorType :: enum {
	User = 0,
	Group = 1,
}

CreatorTypeFilter :: enum {
	User = 0,
	Group = 1,
	All = 2,
}

CustomCameraMode :: enum {
	Default = 0,
	Classic = 1,
	Follow = 2,
}

DataStoreRequestType :: enum {
	GetAsync = 0,
	SetIncrementAsync = 1,
	UpdateAsync = 2,
	GetSortedAsync = 3,
	SetIncrementSortedAsync = 4,
	OnUpdate = 5,
	ListAsync = 6,
	GetVersionAsync = 7,
	RemoveVersionAsync = 8,
	StandardRead = 9,
	StandardWrite = 10,
	StandardList = 11,
	StandardRemove = 12,
	OrderedRead = 13,
	OrderedWrite = 14,
	OrderedList = 15,
	OrderedRemove = 16,
}

DebuggerEndReason :: enum {
	ClientRequest = 0,
	Timeout = 1,
	InvalidHost = 2,
	Disconnected = 3,
	ServerShutdown = 4,
	ServerProtocolMismatch = 5,
	ConfigurationFailed = 6,
	RpcError = 7,
}

DebuggerExceptionBreakMode :: enum {
	Never = 0,
	Always = 1,
	Unhandled = 2,
}

DebuggerFrameType :: enum {
	C = 0,
	Lua = 1,
}

DebuggerPauseReason :: enum {
	Unknown = 0,
	Requested = 1,
	Breakpoint = 2,
	Exception = 3,
	SingleStep = 4,
	Entrypoint = 5,
}

DebuggerStatus :: enum {
	Success = 0,
	Timeout = 1,
	ConnectionLost = 2,
	InvalidResponse = 3,
	InternalError = 4,
	InvalidState = 5,
	RpcError = 6,
	InvalidArgument = 7,
	ConnectionClosed = 8,
}

DefaultScriptSyncFileType :: enum {
	Lua = 0,
	Luau = 1,
}

DevCameraOcclusionMode :: enum {
	Zoom = 0,
	Invisicam = 1,
}

DevComputerCameraMovementMode :: enum {
	UserChoice = 0,
	Classic = 1,
	Follow = 2,
	Orbital = 3,
	CameraToggle = 4,
}

DevComputerMovementMode :: enum {
	UserChoice = 0,
	KeyboardMouse = 1,
	ClickToMove = 2,
	Scriptable = 3,
}

DevTouchCameraMovementMode :: enum {
	UserChoice = 0,
	Classic = 1,
	Follow = 2,
	Orbital = 3,
}

DevTouchMovementMode :: enum {
	UserChoice = 0,
	Thumbstick = 1,
	DPad = 2,
	Thumbpad = 3,
	ClickToMove = 4,
	Scriptable = 5,
	DynamicThumbstick = 6,
}

DeveloperMemoryTag :: enum {
	Internal = 0,
	HttpCache = 1,
	Instances = 2,
	Signals = 3,
	LuaHeap = 4,
	Script = 5,
	PhysicsCollision = 6,
	BaseParts = 7,
	GraphicsSolidModels = 8,
	GraphicsMeshParts = 10,
	GraphicsParticles = 11,
	GraphicsParts = 12,
	GraphicsSpatialHash = 13,
	GraphicsTerrain = 14,
	GraphicsTexture = 15,
	GraphicsTextureCharacter = 16,
	Sounds = 17,
	StreamingSounds = 18,
	TerrainVoxels = 19,
	Gui = 21,
	Animation = 22,
	Navigation = 23,
	GeometryCSG = 24,
	GraphicsSlimModels = 25,
}

DeviceFeatureType :: enum {
	DeviceCapture = 0,
	InExperienceFAE = 1,
}

DeviceForm :: enum {
	Console = 0,
	Phone = 1,
	Tablet = 2,
	Desktop = 3,
	VR = 4,
}

DeviceLevel :: enum {
	Low = 0,
	Medium = 1,
	High = 2,
}

DeviceType :: enum {
	Unknown = 0,
	Desktop = 1,
	Tablet = 2,
	Phone = 3,
}

DialogBehaviorType :: enum {
	SinglePlayer = 0,
	MultiplePlayers = 1,
}

DialogPurpose :: enum {
	Quest = 0,
	Help = 1,
	Shop = 2,
}

DialogTone :: enum {
	Neutral = 0,
	Friendly = 1,
	Enemy = 2,
}

DisplaySize :: enum {
	Small = 0,
	Medium = 1,
	Large = 2,
}

DominantAxis :: enum {
	Width = 0,
	Height = 1,
}

DraftStatusCode :: enum {
	OK = 0,
	DraftOutdated = 1,
	ScriptRemoved = 2,
	DraftCommitted = 3,
}

DragDetectorDragStyle :: enum {
	TranslateLine = 0,
	TranslatePlane = 1,
	TranslatePlaneOrLine = 2,
	TranslateLineOrPlane = 3,
	TranslateViewPlane = 4,
	RotateAxis = 5,
	RotateTrackball = 6,
	Scriptable = 7,
	BestForDevice = 8,
}

DragDetectorPermissionPolicy :: enum {
	Nobody = 0,
	Everybody = 1,
	Scriptable = 2,
}

DragDetectorResponseStyle :: enum {
	Geometric = 0,
	Physical = 1,
	Custom = 2,
}

DraggerCoordinateSpace :: enum {
	Object = 0,
	World = 1,
}

DraggerMovementMode :: enum {
	Geometric = 0,
	Physical = 1,
}

DraggingScrollBar :: enum {
	None = 0,
	Horizontal = 1,
	Vertical = 2,
}

EasingDirection :: enum {
	In = 0,
	Out = 1,
	InOut = 2,
}

EasingStyle :: enum {
	Linear = 0,
	Sine = 1,
	Back = 2,
	Quad = 3,
	Quart = 4,
	Quint = 5,
	Bounce = 6,
	Elastic = 7,
	Exponential = 8,
	Circular = 9,
	Cubic = 10,
}

EditableStatus :: enum {
	Unknown = 0,
	Allowed = 1,
	Disallowed = 2,
}

ElasticBehavior :: enum {
	WhenScrollable = 0,
	Always = 1,
	Never = 2,
}

environmentalPhysicsThrottle :: enum {
	DefaultAuto = 0,
	Disabled = 1,
	Always = 2,
	Skip2 = 3,
	Skip4 = 4,
	Skip8 = 5,
	Skip16 = 6,
}

ExperienceAuthScope :: enum {
	DefaultScope = 0,
	CreatorAssetsCreate = 1,
}

ExperienceEventStatus :: enum {
	Active = 0,
	Cancelled = 1,
	Moderated = 2,
	Unpublished = 3,
	Unknown = 4,
}

ExperienceStateCaptureSelectionMode :: enum {
	Default = 0,
	SafetyHighlightMode = 1,
}

ExperienceStateRecordingLoadMode :: enum {
	NewReplay = 0,
	ContiguousSlice = 1,
	NoncontiguousSlice = 2,
}

ExperienceStateRecordingLoadSourceType :: enum {
	S3Url = 0,
	File = 1,
}

ExperienceStateRecordingPlaybackMode :: enum {
	Undefined = 0,
	Stopped = 1,
	Playing = 2,
	Rewinding = 3,
}

ExplosionType :: enum {
	NoCraters = 0,
	Craters = 1,
}

FACSDataLod :: enum {
	LOD0 = 0,
	LOD1 = 1,
	LODCount = 2,
}

FacialAgeEstimationResultType :: enum {
	Complete = 0,
	Cancel = 1,
	Error = 2,
}

FacialAnimationStreamingState :: enum {
	None = 0,
	Audio = 1,
	Video = 2,
	Place = 4,
	Server = 8,
}

FacsActionUnit :: enum {
	ChinRaiserUpperLip = 0,
	ChinRaiser = 1,
	FlatPucker = 2,
	Funneler = 3,
	LowerLipSuck = 4,
	LipPresser = 5,
	LipsTogether = 6,
	MouthLeft = 7,
	MouthRight = 8,
	Pucker = 9,
	UpperLipSuck = 10,
	LeftCheekPuff = 11,
	LeftDimpler = 12,
	LeftLipCornerDown = 13,
	LeftLowerLipDepressor = 14,
	LeftLipCornerPuller = 15,
	LeftLipStretcher = 16,
	LeftUpperLipRaiser = 17,
	RightCheekPuff = 18,
	RightDimpler = 19,
	RightLipCornerDown = 20,
	RightLowerLipDepressor = 21,
	RightLipCornerPuller = 22,
	RightLipStretcher = 23,
	RightUpperLipRaiser = 24,
	JawDrop = 25,
	JawLeft = 26,
	JawRight = 27,
	Corrugator = 28,
	LeftBrowLowerer = 29,
	LeftOuterBrowRaiser = 30,
	LeftNoseWrinkler = 31,
	LeftInnerBrowRaiser = 32,
	RightBrowLowerer = 33,
	RightOuterBrowRaiser = 34,
	RightInnerBrowRaiser = 35,
	RightNoseWrinkler = 36,
	EyesLookDown = 37,
	EyesLookLeft = 38,
	EyesLookUp = 39,
	EyesLookRight = 40,
	LeftCheekRaiser = 41,
	LeftEyeUpperLidRaiser = 42,
	LeftEyeClosed = 43,
	RightCheekRaiser = 44,
	RightEyeUpperLidRaiser = 45,
	RightEyeClosed = 46,
	TongueDown = 47,
	TongueOut = 48,
	TongueUp = 49,
}

FeatureRestrictionAbuseVector :: enum {
	ExperienceChat = 0,
	Communication = 1,
}

FieldOfViewMode :: enum {
	Vertical = 0,
	Diagonal = 1,
	MaxAxis = 2,
}

FillDirection :: enum {
	Horizontal = 0,
	Vertical = 1,
}

FilterErrorType :: enum {
	BackslashNotEscapingAnything = 0,
	BadBespokeFilter = 1,
	BadName = 2,
	IncompleteOr = 3,
	IncompleteParenthesis = 4,
	InvalidDoubleStar = 5,
	InvalidTilde = 6,
	PropertyBadOperator = 7,
	PropertyDoesNotExist = 8,
	PropertyInvalidField = 9,
	PropertyInvalidValue = 10,
	PropertyUnsupportedFields = 11,
	PropertyUnsupportedProperty = 12,
	UnexpectedNameIndex = 13,
	UnexpectedToken = 14,
	UnfinishedBinaryOperator = 15,
	UnfinishedQuote = 16,
	UnknownBespokeFilter = 17,
	WildcardInProperty = 18,
}

FilterResult :: enum {
	Accepted = 0,
	Rejected = 1,
}

FilterType :: enum {
	Exclude = 0,
	Include = 1,
}

FinishRecordingOperation :: enum {
	Cancel = 0,
	Commit = 1,
	Append = 2,
}

FluidFidelity :: enum {
	Automatic = 0,
	UseCollisionGeometry = 1,
	UsePreciseGeometry = 2,
}

FluidForces :: enum {
	Default = 0,
	Experimental = 1,
}

Font :: enum {
	Legacy = 0,
	Arial = 1,
	ArialBold = 2,
	SourceSans = 3,
	SourceSansBold = 4,
	SourceSansLight = 5,
	SourceSansItalic = 6,
	Bodoni = 7,
	Garamond = 8,
	Cartoon = 9,
	Code = 10,
	Highway = 11,
	SciFi = 12,
	Arcade = 13,
	Fantasy = 14,
	Antique = 15,
	SourceSansSemibold = 16,
	Gotham = 17,
	GothamMedium = 18,
	GothamBold = 19,
	GothamBlack = 20,
	AmaticSC = 21,
	Bangers = 22,
	Creepster = 23,
	DenkOne = 24,
	Fondamento = 25,
	FredokaOne = 26,
	GrenzeGotisch = 27,
	IndieFlower = 28,
	JosefinSans = 29,
	Jura = 30,
	Kalam = 31,
	LuckiestGuy = 32,
	Merriweather = 33,
	Michroma = 34,
	Nunito = 35,
	Oswald = 36,
	PatrickHand = 37,
	PermanentMarker = 38,
	Roboto = 39,
	RobotoCondensed = 40,
	RobotoMono = 41,
	Sarpanch = 42,
	SpecialElite = 43,
	TitilliumWeb = 44,
	Ubuntu = 45,
	Arimo = 50,
	ArimoBold = 51,
}

FontSize :: enum {
	Size8 = 0,
	Size9 = 1,
	Size10 = 2,
	Size11 = 3,
	Size12 = 4,
	Size14 = 5,
	Size18 = 6,
	Size24 = 7,
	Size36 = 8,
	Size48 = 9,
	Size28 = 10,
	Size32 = 11,
	Size42 = 12,
	Size60 = 13,
	Size96 = 14,
}

FontStyle :: enum {
	Normal = 0,
	Italic = 1,
}

FontWeight :: enum {
	Thin = 100,
	ExtraLight = 200,
	Light = 300,
	Regular = 400,
	Medium = 500,
	SemiBold = 600,
	Bold = 700,
	ExtraBold = 800,
	Heavy = 900,
}

ForceLimitMode :: enum {
	Magnitude = 0,
	PerAxis = 1,
}

FormFactor :: enum {
	Symmetric = 0,
	Brick = 1,
	Plate = 2,
	Custom = 3,
}

FrameStyle :: enum {
	Custom = 0,
	ChatBlue = 1,
	ChatGreen = 4,
	ChatRed = 5,
	DropShadow = 6,
}

FramerateManagerMode :: enum {
	Automatic = 0,
	On = 1,
	Off = 2,
}

FriendRequestEvent :: enum {
	Issue = 0,
	Revoke = 1,
	Accept = 2,
	Deny = 3,
}

FriendStatus :: enum {
	Unknown = 0,
	NotFriend = 1,
	Friend = 2,
	FriendRequestSent = 3,
	FriendRequestReceived = 4,
}

FunctionalTestResult :: enum {
	Passed = 0,
	Warning = 1,
	Error = 2,
}

GamepadType :: enum {
	Unknown = 0,
	PS4 = 1,
	PS5 = 2,
	XboxOne = 3,
}

GearGenreSetting :: enum {
	AllGenres = 0,
	MatchingGenreOnly = 1,
}

GearType :: enum {
	MeleeWeapons = 0,
	RangedWeapons = 1,
	Explosives = 2,
	PowerUps = 3,
	NavigationEnhancers = 4,
	MusicalInstruments = 5,
	SocialItems = 6,
	BuildingTools = 7,
	Transport = 8,
}

Genre :: enum {
	All = 0,
	TownAndCity = 1,
	Fantasy = 2,
	SciFi = 3,
	Ninja = 4,
	Scary = 5,
	Pirate = 6,
	Adventure = 7,
	Sports = 8,
	Funny = 9,
	WildWest = 10,
	War = 11,
	SkatePark = 12,
	Tutorial = 13,
}

GraphicsMode :: enum {
	Automatic = 1,
	Direct3D11 = 2,
	OpenGL = 4,
	Metal = 5,
	Vulkan = 6,
	NoGraphics = 9,
}

GraphicsOptimizationMode :: enum {
	Performance = 0,
	Balanced = 1,
	Quality = 2,
}

GroupMembershipStatus :: enum {
	None = 0,
	Joined = 1,
	JoinRequestPending = 2,
	AlreadyMember = 3,
}

GuiState :: enum {
	Idle = 0,
	Hover = 1,
	Press = 2,
	NonInteractable = 3,
}

GuiType :: enum {
	Core = 0,
	Custom = 1,
	PlayerNameplates = 2,
	CustomBillboards = 3,
	CoreBillboards = 4,
}

HandRigDescriptionSide :: enum {
	None = 0,
	Left = 1,
	Right = 2,
}

HandlesStyle :: enum {
	Resize = 0,
	Movement = 1,
	Rotation = 2,
}

HapticEffectType :: enum {
	Custom = 0,
	UIHover = 1,
	UIClick = 2,
	UINotification = 3,
	GameplayExplosion = 4,
	GameplayCollision = 5,
}

HashAlgorithm :: enum {
	Blake2b = 0,
	Blake3 = 1,
	Md5 = 2,
	Sha1 = 3,
	Sha256 = 4,
}

HighlightDepthMode :: enum {
	AlwaysOnTop = 0,
	Occluded = 1,
}

HorizontalAlignment :: enum {
	Center = 0,
	Left = 1,
	Right = 2,
}

HoverAnimateSpeed :: enum {
	VerySlow = 0,
	Slow = 1,
	Medium = 2,
	Fast = 3,
	VeryFast = 4,
}

HttpCachePolicy :: enum {
	None = 0,
	Full = 1,
	DataOnly = 2,
	Default = 3,
	InternalRedirectRefresh = 4,
}

HttpCompression :: enum {
	None = 0,
	Gzip = 1,
}

HttpContentType :: enum {
	ApplicationJson = 0,
	ApplicationXml = 1,
	ApplicationUrlEncoded = 2,
	TextPlain = 3,
	TextXml = 4,
}

HttpError :: enum {
	OK = 0,
	InvalidUrl = 1,
	DnsResolve = 2,
	ConnectFail = 3,
	OutOfMemory = 4,
	TimedOut = 5,
	TooManyRedirects = 6,
	InvalidRedirect = 7,
	NetFail = 8,
	Aborted = 9,
	SslConnectFail = 10,
	SslVerificationFail = 11,
	Unknown = 12,
	ConnectionClosed = 13,
	ServerProtocolError = 14,
	CreatorEnvironmentsNotSupportedByService = 15,
}

HttpRequestType :: enum {
	Default = 0,
	MarketplaceService = 2,
	Players = 7,
	Chat = 15,
	Avatar = 16,
	Analytics = 23,
	Localization = 25,
}

HumanoidCollisionType :: enum {
	OuterBox = 0,
	InnerBox = 1,
}

HumanoidDisplayDistanceType :: enum {
	Viewer = 0,
	Subject = 1,
	None = 2,
}

HumanoidHealthDisplayType :: enum {
	DisplayWhenDamaged = 0,
	AlwaysOn = 1,
	AlwaysOff = 2,
}

HumanoidStateType :: enum {
	FallingDown = 0,
	Ragdoll = 1,
	GettingUp = 2,
	Jumping = 3,
	Swimming = 4,
	Freefall = 5,
	Flying = 6,
	Landed = 7,
	Running = 8,
	RunningNoPhysics = 10,
	StrafingNoPhysics = 11,
	Climbing = 12,
	Seated = 13,
	PlatformStanding = 14,
	Dead = 15,
	Physics = 16,
	None = 18,
}

IKCollisionsMode :: enum {
	NoCollisions = 0,
	OtherMechanismsAnchored = 1,
	IncludeContactedMechanisms = 2,
}

IKControlConstraintSupport :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

IKControlType :: enum {
	Transform = 0,
	Position = 1,
	Rotation = 2,
	LookAt = 3,
}

IXPLoadingStatus :: enum {
	None = 0,
	Pending = 1,
	Initialized = 2,
	ErrorInvalidUser = 3,
	ErrorConnection = 4,
	ErrorJsonParse = 5,
	ErrorTimedOut = 6,
}

ImageAlphaType :: enum {
	Default = 1,
	LockCanvasAlpha = 2,
	LockCanvasColor = 3,
}

ImageCombineType :: enum {
	BlendSourceOver = 1,
	Overwrite = 2,
	Add = 3,
	Multiply = 4,
	AlphaBlend = 5,
}

InOut :: enum {
	Edge = 0,
	Inset = 1,
	Center = 2,
}

InfoType :: enum {
	Asset = 0,
	Product = 1,
	GamePass = 2,
	Subscription = 3,
	Bundle = 4,
}

InitialDockState :: enum {
	Top = 0,
	Bottom = 1,
	Left = 2,
	Right = 3,
	Float = 4,
}

InputActionType :: enum {
	Bool = 0,
	Direction1D = 1,
	Direction2D = 2,
	Direction3D = 3,
	ViewportPosition = 4,
}

InputType :: enum {
	NoInput = 0,
	Constant = 12,
	Sin = 13,
}

IntermediateMeshGenerationResult :: enum {
	HighQualityMesh = 0,
}

InterpolationThrottlingMode :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

InviteState :: enum {
	Placed = 0,
	Accepted = 1,
	Declined = 2,
	Missed = 3,
}

ItemLineAlignment :: enum {
	Automatic = 0,
	Start = 1,
	Center = 2,
	End = 3,
	Stretch = 4,
}

JoinSource :: enum {
	CreatedItemAttribution = 1,
}

JointCreationMode :: enum {
	All = 0,
	Surface = 1,
	None = 2,
}

KeyInterpolationMode :: enum {
	Constant = 0,
	Linear = 1,
	Cubic = 2,
}

KeywordFilterType :: enum {
	Include = 0,
	Exclude = 1,
}

Language :: enum {
	Default = 0,
}

LeftRight :: enum {
	Left = 0,
	Center = 1,
	Right = 2,
}

LexemeType :: enum {
	Eof = 0,
	Name = 1,
	QuotedString = 2,
	Number = 3,
	And = 4,
	Or = 5,
	Equal = 6,
	TildeEqual = 7,
	GreaterThan = 8,
	GreaterThanEqual = 9,
	LessThan = 10,
	LessThanEqual = 11,
	Colon = 12,
	Dot = 13,
	LeftParenthesis = 14,
	RightParenthesis = 15,
	Star = 16,
	DoubleStar = 17,
	ReservedSpecial = 18,
}

LightingStyle :: enum {
	Realistic = 0,
	Soft = 1,
}

Limb :: enum {
	Head = 0,
	Torso = 1,
	LeftArm = 2,
	RightArm = 3,
	LeftLeg = 4,
	RightLeg = 5,
	Unknown = 6,
}

LineJoinMode :: enum {
	Round = 0,
	Bevel = 1,
	Miter = 2,
}

ListDisplayMode :: enum {
	Horizontal = 0,
	Vertical = 1,
}

ListenerLocation :: enum {
	Default = 0,
	None = 1,
	Character = 2,
	Camera = 3,
}

ListenerType :: enum {
	Camera = 0,
	CFrame = 1,
	ObjectPosition = 2,
	ObjectCFrame = 3,
}

LiveEditingAtomicUpdateResponse :: enum {
	Success = 0,
	FailureGuidNotFound = 1,
	FailureHashMismatch = 2,
	FailureOperationIllegal = 3,
}

LiveEditingBroadcastMessageType :: enum {
	Normal = 0,
	Warning = 1,
	Error = 2,
}

LoadCharacterLayeredClothing :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

LoadDynamicHeads :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

LocationType :: enum {
	Character = 0,
	Camera = 1,
	ObjectPosition = 2,
}

LuauTypeCheckMode :: enum {
	Default = 0,
	NoCheck = 1,
	Nonstrict = 2,
	Strict = 3,
}

MakeupType :: enum {
	Face = 0,
	Lip = 1,
	Eye = 2,
}

MarketplaceBulkPurchasePromptStatus :: enum {
	Completed = 1,
	Aborted = 2,
	Error = 3,
}

MarketplaceProductType :: enum {
	AvatarAsset = 1,
	AvatarBundle = 2,
}

MarkupKind :: enum {
	PlainText = 0,
	Markdown = 1,
}

MatchmakingType :: enum {
	Default = 1,
	XboxOnly = 2,
	PlayStationOnly = 3,
}

MaterialPattern :: enum {
	Regular = 0,
	Organic = 1,
}

MembershipType :: enum {
	None = 0,
	BuildersClub = 1,
	TurboBuildersClub = 2,
	OutrageousBuildersClub = 3,
	Premium = 4,
}

MeshPartDetailLevel :: enum {
	DistanceBased = 0,
	Level00 = 1,
	Level01 = 2,
	Level02 = 3,
	Level03 = 4,
	Level04 = 5,
}

MeshPartHeadsAndAccessories :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

MeshScaleUnit :: enum {
	Stud = 0,
	Meter = 1,
	CM = 2,
	MM = 3,
	Foot = 4,
	Inch = 5,
}

MeshType :: enum {
	Head = 0,
	Torso = 1,
	Wedge = 2,
	Sphere = 3,
	Cylinder = 4,
	FileMesh = 5,
	Brick = 6,
	Prism = 7,
	Pyramid = 8,
	ParallelRamp = 9,
	RightAngleRamp = 10,
	CornerWedge = 11,
}

MessageType :: enum {
	MessageOutput = 0,
	MessageInfo = 1,
	MessageWarning = 2,
	MessageError = 3,
}

ModelLevelOfDetail :: enum {
	Automatic = 0,
	StreamingMesh = 1,
	Disabled = 2,
	SLIM = 4,
}

ModelStreamingBehavior :: enum {
	Default = 0,
	Legacy = 1,
	Improved = 2,
}

ModelStreamingMode :: enum {
	Default = 0,
	Atomic = 1,
	Persistent = 2,
	PersistentPerPlayer = 3,
	Nonatomic = 4,
}

ModerationResultCategory :: enum {
	ViolationDetected = 0,
	Borderline = 1,
	NoViolationDetected = 2,
}

ModerationResultLabel :: enum {
	ChildExploitation = 0,
	SuicideSelfInjuryAndHarmfulBehavior = 1,
	ThreatsBullyingAndHarassment = 2,
	TerrorismAndViolentExtremism = 3,
	DiscriminationSlursAndHateSpeech = 4,
	RealWorldSensitiveEvents = 5,
	ViolentContentAndGore = 6,
	RomanticAndSexualContent = 7,
	IllegalAndRegulatedGoodsAndActivities = 8,
	Profanity = 9,
	Other = 100,
}

ModerationStatus :: enum {
	ReviewedApproved = 1,
	ReviewedRejected = 2,
	NotReviewed = 3,
	NotApplicable = 4,
	Invalid = 5,
}

ModifierKey :: enum {
	Shift = 0,
	Ctrl = 1,
	Alt = 2,
	Meta = 3,
}

MouseBehavior :: enum {
	Default = 0,
	LockCenter = 1,
	LockCurrentPosition = 2,
}

MoveState :: enum {
	Stopped = 0,
	Coasting = 1,
	Pushing = 2,
	Stopping = 3,
	AirFree = 4,
}

MoverConstraintRootBehaviorMode :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

MuteState :: enum {
	Unmuted = 0,
	Muted = 1,
}

NameOcclusion :: enum {
	NoOcclusion = 0,
	EnemyOcclusion = 1,
	OccludeAll = 2,
}

NegateOperationHiddenHistory :: enum {
	None = 0,
	NegatedUnion = 1,
	NegatedIntersection = 2,
}

NetworkStatus :: enum {
	Unknown = 0,
	Connected = 1,
	Disconnected = 2,
}

NoiseType :: enum {
	SimplexGabor = 0,
}

NormalId :: enum {
	Right = 0,
	Top = 1,
	Back = 2,
	Left = 3,
	Bottom = 4,
	Front = 5,
}

NotificationButtonType :: enum {
	Primary = 0,
	Secondary = 1,
}

OperationType :: enum {
	Null = 0,
	Union = 1,
	Subtraction = 2,
	Intersection = 3,
	Primitive = 4,
}

OrientationAlignmentMode :: enum {
	OneAttachment = 0,
	TwoAttachment = 1,
}

OutfitSource :: enum {
	All = 1,
	Created = 2,
	Purchased = 3,
}

OutfitType :: enum {
	All = 1,
	Avatar = 2,
	DynamicHead = 3,
	Shoes = 4,
}

OutputLayoutMode :: enum {
	Horizontal = 0,
	Vertical = 1,
}

OverrideMouseIconBehavior :: enum {
	None = 0,
	ForceShow = 1,
	ForceHide = 2,
}

PackagePermission :: enum {
	None = 0,
	NoAccess = 1,
	Revoked = 2,
	UseView = 3,
	Edit = 4,
	Own = 5,
}

PartType :: enum {
	Ball = 0,
	Block = 1,
	Cylinder = 2,
	Wedge = 3,
	CornerWedge = 4,
}

ParticleEmitterShape :: enum {
	Box = 0,
	Sphere = 1,
	Cylinder = 2,
	Disc = 3,
}

ParticleEmitterShapeInOut :: enum {
	Outward = 0,
	Inward = 1,
	InAndOut = 2,
}

ParticleEmitterShapeStyle :: enum {
	Volume = 0,
	Surface = 1,
}

ParticleFlipbookLayout :: enum {
	None = 0,
	Grid2x2 = 1,
	Grid4x4 = 2,
	Grid8x8 = 3,
	Custom = 4,
}

ParticleFlipbookMode :: enum {
	Loop = 0,
	OneShot = 1,
	PingPong = 2,
	Random = 3,
}

ParticleFlipbookTextureCompatible :: enum {
	NotCompatible = 0,
	Compatible = 1,
	Unknown = 2,
}

ParticleOrientation :: enum {
	FacingCamera = 0,
	FacingCameraWorldUp = 1,
	VelocityParallel = 2,
	VelocityPerpendicular = 3,
}

PathStatus :: enum {
	Success = 0,
	NoPath = 5,
	ClosestNoPath = 1,
	ClosestOutOfRange = 2,
	FailStartNotEmpty = 3,
	FailFinishNotEmpty = 4,
}

PathWaypointAction :: enum {
	Walk = 0,
	Jump = 1,
	Custom = 2,
}

PathfindingUseImprovedSearch :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

PeoplePageLayout :: enum {
	Card = 0,
	List = 1,
}

PerformanceOverlayMode :: enum {
	Overdraw = 0,
	Transparent = 1,
	Decals = 2,
	Lights = 3,
}

PermissionLevelShown :: enum {
	Game = 0,
	Studio = 3,
}

PhysicsSimulationRate :: enum {
	Fixed240Hz = 0,
	Fixed120Hz = 1,
	Fixed60Hz = 2,
}

PhysicsSteppingMethod :: enum {
	Default = 0,
	Fixed = 1,
	Adaptive = 2,
}

PlaceContentPreference :: enum {
	None = 0,
	All = 1,
	MentionsAndReplies = 2,
	Unknown = 3,
}

PlacePublishType :: enum {
	None = 0,
	Publish = 1,
	Save = 2,
}

Platform :: enum {
	Windows = 0,
	OSX = 1,
	IOS = 2,
	Android = 3,
	XBoxOne = 4,
	PS4 = 5,
	PS3 = 6,
	XBox360 = 7,
	WiiU = 8,
	NX = 9,
	Ouya = 10,
	AndroidTV = 11,
	Chromecast = 12,
	Linux = 13,
	SteamOS = 14,
	WebOS = 15,
	DOS = 16,
	BeOS = 17,
	UWP = 18,
	PS5 = 19,
	MetaOS = 20,
	FreeBSD = 21,
	None = 22,
}

PlaybackState :: enum {
	Begin = 0,
	Delayed = 1,
	Playing = 2,
	Paused = 3,
	Completed = 4,
	Cancelled = 5,
}

PlayerActions :: enum {
	CharacterForward = 0,
	CharacterBackward = 1,
	CharacterLeft = 2,
	CharacterRight = 3,
	CharacterJump = 4,
}

PlayerCharacterDestroyBehavior :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

PlayerChatType :: enum {
	All = 0,
	Team = 1,
	Whisper = 2,
}

PlayerDataErrorState :: enum {
	LoadFailed = 0,
	FlushFailed = 1,
	ReleaseFailed = 2,
	None = 3,
}

PlayerDataLoadFailureBehavior :: enum {
	Failure = 0,
	FallbackToDefault = 1,
	Kick = 2,
}

PlayerExitReason :: enum {
	Unknown = 0,
	PlatformKick = 1,
	CreatorKick = 2,
}

PoseEasingDirection :: enum {
	In = 0,
	Out = 1,
	InOut = 2,
}

PoseEasingStyle :: enum {
	Linear = 0,
	Constant = 1,
	Elastic = 2,
	Cubic = 3,
	Bounce = 4,
	CubicV2 = 5,
}

PositionAlignmentMode :: enum {
	OneAttachment = 0,
	TwoAttachment = 1,
}

PredictionMode :: enum {
	Automatic = 0,
	On = 1,
	Off = 2,
}

PredictionStatus :: enum {
	Authoritative = 0,
	Predicted = 1,
	None = 2,
}

PreferredInput :: enum {
	KeyboardAndMouse = 0,
	Gamepad = 1,
	Touch = 2,
}

PreferredTextSize :: enum {
	Medium = 1,
	Large = 2,
	Larger = 3,
	Largest = 4,
}

PrimalPhysicsSolver :: enum {
	Default = 0,
	Experimental = 1,
	Disabled = 2,
}

PrimitiveType :: enum {
	Null = 0,
	Ball = 1,
	Cylinder = 2,
	Block = 3,
	Wedge = 4,
	CornerWedge = 5,
}

PrivilegeType :: enum {
	Owner = 255,
	Admin = 240,
	Member = 128,
	Visitor = 10,
	Banned = 0,
}

ProductLocationRestriction :: enum {
	AvatarShop = 0,
	AllowedGames = 1,
	AllGames = 2,
}

ProductPurchaseChannel :: enum {
	InExperience = 1,
	ExperienceDetailsPage = 2,
	AdReward = 3,
	CommerceProduct = 4,
}

ProductPurchaseDecision :: enum {
	NotProcessedYet = 0,
	PurchaseGranted = 1,
}

PromptCreateAssetResult :: enum {
	Success = 1,
	PermissionDenied = 2,
	Timeout = 3,
	UploadFailed = 4,
	NoUserInput = 5,
	UnknownFailure = 6,
	UGCValidationFailed = 7,
	ModeratedName = 8,
	PurchaseFailure = 9,
	TokenInvalid = 10,
}

PromptCreateAvatarResult :: enum {
	Success = 1,
	PermissionDenied = 2,
	Timeout = 3,
	UploadFailed = 4,
	NoUserInput = 5,
	InvalidHumanoidDescription = 6,
	UGCValidationFailed = 7,
	ModeratedName = 8,
	MaxOutfits = 9,
	PurchaseFailure = 10,
	UnknownFailure = 11,
	TokenInvalid = 12,
}

PromptExperienceDetailsResult :: enum {
	PromptClosed = 0,
	TeleportAttempted = 1,
}

PromptLinkSharingResult :: enum {
	Success = 1,
	PlayerLeft = 2,
	InvalidLaunchData = 3,
}

PromptPublishAssetResult :: enum {
	Success = 1,
	PermissionDenied = 2,
	Timeout = 3,
	UploadFailed = 4,
	NoUserInput = 5,
	UnknownFailure = 6,
}

PropertyStatus :: enum {
	Ok = 0,
	Warning = 1,
	Error = 2,
}

ProximityPromptExclusivity :: enum {
	OnePerButton = 0,
	OneGlobally = 1,
	AlwaysShow = 2,
}

ProximityPromptInputType :: enum {
	Keyboard = 0,
	Gamepad = 1,
	Touch = 2,
}

ProximityPromptStyle :: enum {
	Default = 0,
	Custom = 1,
}

QualityLevel :: enum {
	Automatic = 0,
	Level01 = 1,
	Level02 = 2,
	Level03 = 3,
	Level04 = 4,
	Level05 = 5,
	Level06 = 6,
	Level07 = 7,
	Level08 = 8,
	Level09 = 9,
	Level10 = 10,
	Level11 = 11,
	Level12 = 12,
	Level13 = 13,
	Level14 = 14,
	Level15 = 15,
	Level16 = 16,
	Level17 = 17,
	Level18 = 18,
	Level19 = 19,
	Level20 = 20,
	Level21 = 21,
}

R15CollisionType :: enum {
	OuterBox = 0,
	InnerBox = 1,
}

RaycastFilterType :: enum {
	Exclude = 0,
	Include = 1,
}

ReadCapturesFromGalleryResult :: enum {
	Success = 0,
	NeedPermission = 1,
}

RecommendationActionType :: enum {
	AddReaction = 0,
	RemoveReaction = 1,
	Share = 2,
	Report = 3,
	Comment = 4,
	Play = 5,
	Purchase = 6,
}

RecommendationDepartureIntent :: enum {
	Neutral = 0,
	Positive = 1,
	Negative = 2,
}

RecommendationImpressionType :: enum {
	View = 0,
	NotViewable = 1,
}

RecommendationItemContentType :: enum {
	Static = 0,
	Dynamic = 1,
	Interactive = 2,
}

RecommendationItemVisibility :: enum {
	Private = 0,
	Public = 1,
}

RejectCharacterDeletions :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

RenderFidelity :: enum {
	Automatic = 0,
	Precise = 1,
	Performance = 2,
}

RenderPriority :: enum {
	First = 0,
	Input = 100,
	Camera = 200,
	Character = 300,
	Last = 2000,
}

RenderingCacheOptimizationMode :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

RenderingTestComparisonMethod :: enum {
	psnr = 0,
	diff = 1,
}

ReplicateInstanceDestroySetting :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

ResamplerMode :: enum {
	Default = 0,
	Pixelated = 1,
}

ReservedHighlightId :: enum {
	Standard = 0,
	Selection = 524288,
	Hover = 262144,
	Active = 131072,
}

RestPose :: enum {
	Default = 0,
	RotationsReset = 1,
	Custom = 2,
}

RestPoseModel :: enum {
	FromRigInACE = 0,
	FromRigInFile = 1,
}

ReturnKeyType :: enum {
	Default = 0,
	Done = 1,
	Go = 2,
	Next = 3,
	Search = 4,
	Send = 5,
}

ReverbType :: enum {
	NoReverb = 0,
	GenericReverb = 1,
	PaddedCell = 2,
	Room = 3,
	Bathroom = 4,
	LivingRoom = 5,
	StoneRoom = 6,
	Auditorium = 7,
	ConcertHall = 8,
	Cave = 9,
	Arena = 10,
	Hangar = 11,
	CarpettedHallway = 12,
	Hallway = 13,
	StoneCorridor = 14,
	Alley = 15,
	Forest = 16,
	City = 17,
	Mountains = 18,
	Quarry = 19,
	Plain = 20,
	ParkingLot = 21,
	SewerPipe = 22,
	UnderWater = 23,
}

ReviewableContentState :: enum {
	Pending = 0,
	Completed = 1,
	Failed = 2,
}

RibbonTool :: enum {
	Select = 0,
	Scale = 1,
	Rotate = 2,
	Move = 3,
	Transform = 4,
	ColorPicker = 5,
	MaterialPicker = 6,
	Group = 7,
	Ungroup = 8,
	None = 9,
	PivotEditor = 10,
}

RigLabel :: enum {
	Invalid = 0,
	Root = 1,
	Pelvis = 2,
	Waist = 3,
	Chest = 4,
	Neck = 5,
	HeadBase = 6,
	LeftClavicle = 7,
	LeftShoulder = 8,
	LeftElbow = 9,
	LeftWrist = 10,
	RightClavicle = 11,
	RightShoulder = 12,
	RightElbow = 13,
	RightWrist = 14,
	LeftHip = 15,
	LeftKnee = 16,
	LeftAnkle = 17,
	LeftToes = 18,
	RightHip = 19,
	RightKnee = 20,
	RightAnkle = 21,
	RightToes = 22,
}

RigScale :: enum {
	Default = 0,
	Rthro = 1,
	RthroNarrow = 2,
}

RigType :: enum {
	R15 = 0,
	CustomHumanoid = 1,
	Custom = 2,
	None = 3,
}

RollOffMode :: enum {
	Inverse = 0,
	Linear = 1,
	LinearSquare = 2,
	InverseTapered = 3,
}

RolloutState :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

RotationOrder :: enum {
	XYZ = 0,
	XZY = 1,
	YZX = 2,
	YXZ = 3,
	ZXY = 4,
	ZYX = 5,
}

RotationType :: enum {
	MovementRelative = 0,
	CameraRelative = 1,
}

RsvpStatus :: enum {
	None = 0,
	Going = 1,
	NotGoing = 2,
}

RtlTextSupport :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

RunContext :: enum {
	Legacy = 0,
	Server = 1,
	Client = 2,
	Plugin = 3,
}

RunState :: enum {
	Stopped = 0,
	Running = 1,
	Paused = 2,
}

RuntimeUndoBehavior :: enum {
	Aggregate = 0,
	Snapshot = 1,
	Hybrid = 2,
}

SafeAreaCompatibility :: enum {
	None = 0,
	FullscreenExtension = 1,
}

SalesTypeFilter :: enum {
	All = 1,
	Collectibles = 2,
	Premium = 3,
	TimedOptions = 4,
}

SandboxedInstanceMode :: enum {
	Default = 0,
	Experimental = 1,
}

SaveAvatarThumbnailCustomizationFailure :: enum {
	BadThumbnailType = 1,
	BadYRotDeg = 2,
	BadFieldOfViewDeg = 3,
	BadDistanceScale = 4,
	Other = 5,
	Throttled = 6,
}

SaveFilter :: enum {
	SaveWorld = 0,
	SaveGame = 1,
	SaveAll = 2,
}

SavedQualitySetting :: enum {
	Automatic = 0,
	QualityLevel1 = 1,
	QualityLevel2 = 2,
	QualityLevel3 = 3,
	QualityLevel4 = 4,
	QualityLevel5 = 5,
	QualityLevel6 = 6,
	QualityLevel7 = 7,
	QualityLevel8 = 8,
	QualityLevel9 = 9,
	QualityLevel10 = 10,
}

ScaleType :: enum {
	Stretch = 0,
	Slice = 1,
	Tile = 2,
	Fit = 3,
	Crop = 4,
}

ScopeCheckResult :: enum {
	ConsentAccepted = 0,
	InvalidScopes = 1,
	Timeout = 2,
	NoUserInput = 3,
	BackendError = 4,
	UnexpectedError = 5,
	InvalidArgument = 6,
	ConsentDenied = 7,
}

ScreenInsets :: enum {
	None = 0,
	DeviceSafeInsets = 1,
	CoreUISafeInsets = 2,
	TopbarSafeInsets = 3,
}

ScreenOrientation :: enum {
	LandscapeLeft = 0,
	LandscapeRight = 1,
	LandscapeSensor = 2,
	Portrait = 3,
	Sensor = 4,
}

ScrollBarInset :: enum {
	None = 0,
	ScrollBar = 1,
	Always = 2,
}

ScrollingDirection :: enum {
	X = 1,
	Y = 2,
	XY = 4,
}

SecurityCapability :: enum {
	RunClientScript = 0,
	RunServerScript = 1,
	AccessOutsideWrite = 2,
	AssetRequire = 3,
	LoadString = 4,
	ScriptGlobals = 5,
	CreateInstances = 6,
	Basic = 7,
	Audio = 8,
	DataStore = 9,
	Network = 10,
	Physics = 11,
	UI = 12,
	CSG = 13,
	Chat = 14,
	Animation = 15,
	Avatar = 16,
	Input = 17,
	Environment = 18,
	RemoteEvent = 19,
	UnreliableRemoteEvent = 73,
	LegacySound = 20,
	Players = 21,
	CapabilityControl = 22,
	Plugin = 23,
	LocalUser = 24,
	WritePlayer = 25,
	Unassigned = 28,
	InternalTest = 29,
	PluginOrOpenCloud = 30,
	Assistant = 31,
	RemoteCommand = 32,
}

SelectionBehavior :: enum {
	Escape = 0,
	Stop = 1,
}

SelectionRenderMode :: enum {
	Outlines = 0,
	BoundingBoxes = 1,
	Both = 2,
}

SelfViewPosition :: enum {
	LastPosition = 0,
	TopLeft = 1,
	TopRight = 2,
	BottomLeft = 3,
	BottomRight = 4,
}

SensorMode :: enum {
	Floor = 0,
	Ladder = 1,
}

SensorUpdateType :: enum {
	OnRead = 0,
	Manual = 1,
}

ServerLiveEditingMode :: enum {
	Uninitialized = 0,
	Enabled = 1,
	Disabled = 2,
}

ServiceVisibility :: enum {
	Always = 0,
	Off = 1,
	WithChildren = 2,
}

Severity :: enum {
	Error = 1,
	Warning = 2,
	Information = 3,
	Hint = 4,
}

ShowAdResult :: enum {
	ShowCompleted = 1,
	AdNotReady = 2,
	AdAlreadyShowing = 3,
	InternalError = 4,
	ShowInterrupted = 5,
	InsufficientMemory = 6,
}

SignalBehavior :: enum {
	Default = 0,
	Immediate = 1,
	Deferred = 2,
	AncestryDeferred = 3,
}

SizeConstraint :: enum {
	RelativeXY = 0,
	RelativeXX = 1,
	RelativeYY = 2,
}

SolverConvergenceMetricType :: enum {
	IterationBased = 0,
	AlgorithmAgnostic = 1,
}

SolverConvergenceVisualizationMode :: enum {
	Disabled = 0,
	PerIsland = 1,
	PerEdge = 2,
}

SortDirection :: enum {
	Ascending = 0,
	Descending = 1,
}

SortOrder :: enum {
	Name = 0,
	Custom = 1,
	LayoutOrder = 2,
}

SpecialKey :: enum {
	Insert = 0,
	Home = 1,
	End = 2,
	PageUp = 3,
	PageDown = 4,
	ChatHotkey = 5,
}

StartCorner :: enum {
	TopLeft = 0,
	TopRight = 1,
	BottomLeft = 2,
	BottomRight = 3,
}

StateObjectFieldType :: enum {
	Boolean = 0,
	CFrame = 1,
	Color3 = 2,
	Float = 3,
	Instance = 4,
	Random = 5,
	Vector2 = 6,
	Vector3 = 7,
	INVALID = 8,
}

Status :: enum {
	Poison = 0,
	Confusion = 1,
}

StepFrequency :: enum {
	Hz60 = 0,
	Hz30 = 1,
	Hz15 = 2,
	Hz10 = 3,
	Hz5 = 4,
	Hz1 = 5,
}

StreamOutBehavior :: enum {
	Default = 0,
	LowMemory = 1,
	Opportunistic = 2,
}

StreamingIntegrityMode :: enum {
	Default = 0,
	Disabled = 1,
	MinimumRadiusPause = 2,
	PauseOutsideLoadedArea = 3,
}

StreamingPauseMode :: enum {
	Default = 0,
	Disabled = 1,
	ClientPhysicsPause = 2,
}

StrokeSizingMode :: enum {
	FixedSize = 0,
	ScaledSize = 1,
}

StudioCloseMode :: enum {
	None = 0,
	CloseStudio = 1,
	CloseDoc = 2,
	LogOut = 3,
}

StudioDataModelType :: enum {
	Edit = 0,
	PlayClient = 1,
	PlayServer = 2,
	Standalone = 3,
	None = 4,
}

StudioPlaceUpdateFailureReason :: enum {
	Other = 0,
	TeamCreateConflict = 1,
}

StudioScriptEditorColorCategories :: enum {
	Default = 0,
	Operator = 1,
	Number = 2,
	String = 3,
	Comment = 4,
	Keyword = 5,
	Builtin = 6,
	Method = 7,
	Property = 8,
	Nil = 9,
	Bool = 10,
	Function = 11,
	Local = 12,
	Self = 13,
	LuauKeyword = 14,
	FunctionName = 15,
	TODO = 16,
	Background = 17,
	SelectionText = 18,
	SelectionBackground = 19,
	FindSelectionBackground = 20,
	MatchingWordBackground = 21,
	Warning = 22,
	Error = 23,
	Info = 24,
	Hint = 25,
	Whitespace = 26,
	ActiveLine = 27,
	DebuggerCurrentLine = 28,
	DebuggerErrorLine = 29,
	Ruler = 30,
	Bracket = 31,
	Type = 32,
	MenuPrimaryText = 33,
	MenuSecondaryText = 34,
	MenuSelectedText = 35,
	MenuBackground = 36,
	MenuSelectedBackground = 37,
	MenuScrollbarBackground = 38,
	MenuScrollbarHandle = 39,
	MenuBorder = 40,
	DocViewCodeBackground = 41,
	AICOOverlayText = 42,
	AICOOverlayButtonBackground = 43,
	AICOOverlayButtonBackgroundHover = 44,
	AICOOverlayButtonBackgroundPressed = 45,
	IndentationRuler = 46,
}

StudioScriptEditorColorPresets :: enum {
	Extra1 = 1,
	Extra2 = 2,
	Custom = 3,
}

StudioStyleGuideColor :: enum {
	MainBackground = 0,
	Titlebar = 1,
	Dropdown = 2,
	Tooltip = 3,
	Notification = 4,
	ScrollBar = 5,
	ScrollBarBackground = 6,
	TabBar = 7,
	Tab = 8,
	FilterButtonDefault = 9,
	FilterButtonHover = 10,
	FilterButtonChecked = 11,
	FilterButtonAccent = 12,
	FilterButtonBorder = 13,
	FilterButtonBorderAlt = 14,
	RibbonTab = 15,
	RibbonTabTopBar = 16,
	Button = 17,
	MainButton = 18,
	RibbonButton = 19,
	ViewPortBackground = 20,
	InputFieldBackground = 21,
	Item = 22,
	TableItem = 23,
	CategoryItem = 24,
	GameSettingsTableItem = 25,
	GameSettingsTooltip = 26,
	EmulatorBar = 27,
	EmulatorDropDown = 28,
	ColorPickerFrame = 29,
	CurrentMarker = 30,
	Border = 31,
	DropShadow = 32,
	Shadow = 33,
	Light = 34,
	Dark = 35,
	Mid = 36,
	MainText = 37,
	SubText = 38,
	TitlebarText = 39,
	BrightText = 40,
	DimmedText = 41,
	LinkText = 42,
	WarningText = 43,
	ErrorText = 44,
	InfoText = 45,
	SensitiveText = 46,
	ScriptSideWidget = 47,
	ScriptBackground = 48,
	ScriptText = 49,
	ScriptSelectionText = 50,
	ScriptSelectionBackground = 51,
	ScriptFindSelectionBackground = 52,
	ScriptMatchingWordSelectionBackground = 53,
	ScriptOperator = 54,
	ScriptNumber = 55,
	ScriptString = 56,
	ScriptComment = 57,
	ScriptKeyword = 58,
	ScriptBuiltInFunction = 59,
	ScriptWarning = 60,
	ScriptError = 61,
	ScriptInformation = 62,
	ScriptHint = 63,
	ScriptWhitespace = 64,
	ScriptRuler = 65,
	DocViewCodeBackground = 66,
	DebuggerCurrentLine = 67,
	DebuggerErrorLine = 68,
	DiffFilePathText = 69,
	DiffTextHunkInfo = 70,
	DiffTextNoChange = 71,
	DiffTextAddition = 72,
	DiffTextDeletion = 73,
	DiffTextSeparatorBackground = 74,
	DiffTextNoChangeBackground = 75,
	DiffTextAdditionBackground = 76,
	DiffTextDeletionBackground = 77,
	DiffLineNum = 78,
	DiffLineNumSeparatorBackground = 79,
	DiffLineNumNoChangeBackground = 80,
	DiffLineNumAdditionBackground = 81,
	DiffLineNumDeletionBackground = 82,
	DiffFilePathBackground = 83,
	DiffFilePathBorder = 84,
	ChatIncomingBgColor = 85,
	ChatIncomingTextColor = 86,
	ChatOutgoingBgColor = 87,
	ChatOutgoingTextColor = 88,
	ChatModeratedMessageColor = 89,
	Separator = 90,
	ButtonBorder = 91,
	ButtonText = 92,
	InputFieldBorder = 93,
	CheckedFieldBackground = 94,
	CheckedFieldBorder = 95,
	CheckedFieldIndicator = 96,
	HeaderSection = 97,
	Midlight = 98,
	StatusBar = 99,
	DialogButton = 100,
	DialogButtonText = 101,
	DialogButtonBorder = 102,
	DialogMainButton = 103,
	DialogMainButtonText = 104,
	InfoBarWarningBackground = 105,
	InfoBarWarningText = 106,
	ScriptEditorCurrentLine = 107,
	ScriptMethod = 108,
	ScriptProperty = 109,
	ScriptNil = 110,
	ScriptBool = 111,
	ScriptFunction = 112,
	ScriptLocal = 113,
	ScriptSelf = 114,
	ScriptLuauKeyword = 115,
	ScriptFunctionName = 116,
	ScriptTodo = 117,
	ScriptBracket = 118,
	AttributeCog = 119,
	AICOOverlayText = 128,
	AICOOverlayButtonBackground = 129,
	AICOOverlayButtonBackgroundHover = 130,
	AICOOverlayButtonBackgroundPressed = 131,
	OnboardingCover = 132,
	OnboardingHighlight = 133,
	OnboardingShadow = 134,
	BreakpointMarker = 136,
	DiffLineNumHover = 137,
	DiffLineNumSeparatorBackgroundHover = 138,
}

StudioStyleGuideModifier :: enum {
	Default = 0,
	Selected = 1,
	Pressed = 2,
	Disabled = 3,
	Hover = 4,
}

Style :: enum {
	AlternatingSupports = 0,
	BridgeStyleSupports = 1,
	NoSupports = 2,
}

SubscriptionExpirationReason :: enum {
	ProductInactive = 0,
	ProductDeleted = 1,
	SubscriberCancelled = 2,
	SubscriberRefunded = 3,
	Lapsed = 4,
}

SubscriptionPaymentStatus :: enum {
	Paid = 0,
	Refunded = 1,
}

SubscriptionPeriod :: enum {
	Month = 0,
}

SubscriptionState :: enum {
	NeverSubscribed = 0,
	SubscribedWillRenew = 1,
	SubscribedWillNotRenew = 2,
	SubscribedRenewalPaymentPending = 3,
	Expired = 4,
}

SurfaceConstraint :: enum {
	None = 0,
	Hinge = 1,
	SteppingMotor = 2,
	Motor = 3,
}

SurfaceGuiShape :: enum {
	Flat = 0,
	CurvedHorizontally = 1,
}

SurfaceGuiSizingMode :: enum {
	FixedSize = 0,
	PixelsPerStud = 1,
}

SurfaceType :: enum {
	Smooth = 0,
	Glue = 1,
	Weld = 2,
	Studs = 3,
	Inlet = 4,
	Universal = 5,
	Hinge = 6,
	Motor = 7,
	SteppingMotor = 8,
	SmoothNoOutlines = 10,
}

SwipeDirection :: enum {
	Right = 0,
	Left = 1,
	Up = 2,
	Down = 3,
	None = 4,
}

SystemThemeValue :: enum {
	error = 0,
	light = 1,
	dark = 2,
	systemLight = 3,
	systemDark = 4,
}

TableMajorAxis :: enum {
	RowMajor = 0,
	ColumnMajor = 1,
}

TeamCreateErrorState :: enum {
	PlaceSizeTooLarge = 0,
	PlaceSizeApproachingLimit = 1,
	PlaceUploadFailing = 2,
	NoError = 3,
}

Technology :: enum {
	Voxel = 1,
	Compatibility = 2,
	ShadowMap = 3,
	Future = 4,
	Legacy = 0,
	Unified = 5,
}

TelemetryBackend :: enum {
	UNSPECIFIED = 0,
	EventIngest = 1,
	Points = 2,
	Teletune = 3,
	EphemeralCounter = 4,
	EphemeralStat = 5,
	Counter = 6,
	Stat = 7,
}

TelemetryStandardizedField :: enum {
	AddDatacenterId = 0,
	AddPlaceId = 1,
	AddUniverseId = 2,
	AddPlaceInstanceId = 3,
	AddPlaySessionId = 4,
	AddCurrentContextName = 5,
	AddOsInfo = 6,
	AddArchitectureInfo = 7,
	AddCpuInfo = 8,
	AddMemoryInfo = 9,
	AddSessionInfo = 10,
}

TeleportMethod :: enum {
	TeleportToSpawnByName = 0,
	TeleportToPlaceInstance = 1,
	TeleportToPrivateServer = 2,
	TeleportPartyAsync = 3,
	TeleportToVIPServer = 4,
	TeleportToInstanceBack = 5,
	TeleportUnknown = 6,
}

TeleportResult :: enum {
	Success = 0,
	Failure = 1,
	GameNotFound = 2,
	GameEnded = 3,
	GameFull = 4,
	Unauthorized = 5,
	Flooded = 6,
	IsTeleporting = 7,
}

TeleportState :: enum {
	RequestedFromServer = 0,
	Started = 1,
	WaitingForServer = 2,
	Failed = 3,
	InProgress = 4,
}

TeleportType :: enum {
	ToPlace = 0,
	ToInstance = 1,
	ToReservedServer = 2,
	ToVIPServer = 3,
	ToInstanceBack = 4,
}

TerrainAcquisitionMethod :: enum {
	None = 0,
	Legacy = 1,
	Template = 2,
	Generate = 3,
	Import = 4,
	Convert = 5,
	EditAddTool = 6,
	EditSeaLevelTool = 7,
	EditReplaceTool = 8,
	RegionFillTool = 9,
	RegionPasteTool = 10,
	Other = 11,
}

TerrainFace :: enum {
	Top = 0,
	Side = 1,
	Bottom = 2,
}

TextChatMessageStatus :: enum {
	Unknown = 1,
	Success = 2,
	Sending = 3,
	TextFilterFailed = 4,
	Floodchecked = 5,
	InvalidPrivacySettings = 6,
	InvalidTextChannelPermissions = 7,
	MessageTooLong = 8,
	ModerationTimeout = 9,
}

TextDirection :: enum {
	Auto = 0,
	LeftToRight = 1,
	RightToLeft = 2,
}

TextFilterContext :: enum {
	PublicChat = 1,
	PrivateChat = 2,
}

TextInputType :: enum {
	Default = 0,
	NoSuggestions = 1,
	Number = 2,
	Email = 3,
	Phone = 4,
	Password = 5,
	PasswordShown = 6,
	Username = 7,
	OneTimePassword = 8,
}

TextTruncate :: enum {
	None = 0,
	AtEnd = 1,
	SplitWord = 2,
}

TextXAlignment :: enum {
	Left = 0,
	Right = 1,
	Center = 2,
}

TextYAlignment :: enum {
	Top = 0,
	Center = 1,
	Bottom = 2,
}

TextureMode :: enum {
	Stretch = 0,
	Wrap = 1,
	Static = 2,
}

TextureQueryType :: enum {
	NonHumanoid = 0,
	NonHumanoidOrphaned = 1,
	Humanoid = 2,
	HumanoidOrphaned = 3,
}

ThreadPoolConfig :: enum {
	PerCore4 = 104,
	PerCore3 = 103,
	PerCore2 = 102,
	PerCore1 = 101,
	Auto = 0,
	Threads1 = 1,
	Threads2 = 2,
	Threads3 = 3,
	Threads4 = 4,
	Threads8 = 8,
	Threads16 = 16,
}

ThrottlingPriority :: enum {
	Extreme = 2,
	ElevatedOnServer = 1,
	Default = 0,
}

ThumbnailSize :: enum {
	Size48x48 = 0,
	Size180x180 = 1,
	Size420x420 = 2,
	Size60x60 = 3,
	Size100x100 = 4,
	Size150x150 = 5,
	Size352x352 = 6,
}

ThumbnailType :: enum {
	HeadShot = 0,
	AvatarBust = 1,
	AvatarThumbnail = 2,
}

TickCountSampleMethod :: enum {
	Fast = 0,
	Benchmark = 1,
	Precise = 2,
}

TonemapperPreset :: enum {
	Default = 0,
	Retro = 1,
}

TopBottom :: enum {
	Top = 0,
	Center = 1,
	Bottom = 2,
}

TouchCameraMovementMode :: enum {
	Default = 0,
	Classic = 1,
	Follow = 2,
	Orbital = 3,
}

Path3DMode :: enum {
	Linear = 0, // "Linear"
	Bezier = 1, // "Bezier"
	CatmullRom = 2, // "CatmullRom"
	Hermite = 3, // "Hermite"
}

KinemiumDownscaleMode :: enum {
	Nearest = 1,
	Linear = 2,
	Box = 3,
}

PluginIntents :: enum {
	Filesystem = 1,
	FFI = 2,
	Sound = 3,
	Graphics = 4,
	UI = 5,
	Input = 6,
	Threading = 7,
	Network = 8,
	Audio = 9,
	Rendering = 10,
	Physics = 11,
	Serialization = 13,
	Debugging = 14,
	CSG = 15,
}

KinemiumUpscaleMode :: enum {
	Nearest = 1,
	Linear = 2,
	Bicubic = 3,
	Lanczos = 4,
}

RigType :: enum {
	Rig15 = 1,
	Custom = 2,
}

KinemiumBloomMode :: enum {
	Mix = 1,
	Additive = 2,
	Screen = 3,
}

KinemiumFogMode :: enum {
	Linear = 1,
	Exponential = 2,
	Exponential2 = 3,
}

WorkspaceMaterialMode :: enum {
	Compressed = 1,
	Uncompressed = 2,
}

KinemiumTonemapMode :: enum {
	ACES = 1,
	Reinhard = 2,
	Filmic = 3,
	Hejl = 4,
	ACESFilmic = 5,
}

KinemiumOutputMode :: enum {
	Scene = 1,
	Albedo = 2,
	Normal = 3,
	ORM = 4,
	Diffuse = 5,
	Specular = 6,
	SSAO = 7,
	SSIL = 8,
	SSGI = 9,
	SSR = 10,
	Bloom = 11,
	DOF = 12,
}

ParticleTransparencyMode :: enum {
	Disabled = 0,
	Prepass = 1,
	Alpha = 2,
}

ParticleBlendMode :: enum {
	Mix = 0,
	Additive = 1,
	Multiply = 2,
	PremultipliedAlpha = 3,
}

ParticleCullMode :: enum {
	None = 0,
	Back = 1,
	Front = 2,
}

ParticleBillboardMode :: enum {
	Disabled = 0,
	Front = 1,
	YAxis = 2,
}

ParticleFlipbookMode :: enum {
	Loop = 0,
	OneShot = 1,
	PingPong = 2,
	Random = 3,
}

UIParticleEmitterShape :: enum {
	Point = 0,
	Box = 1,
	Circle = 2,
	Ring = 3,
}

KinemiumGraphicsPreset :: enum {
	Off = 0, // "off"
	Low = 1, // "low"
	Medium = 2, // "medium"
	High = 3, // "high"
}

KeyCode :: enum {
	None = 0,
	Space = 32,
	Quote = 39,
	Comma = 44,
	Minus = 45,
	Period = 46,
	Slash = 47,
	Zero = 48,
	One = 49,
	Two = 50,
	Three = 51,
	Four = 52,
	Five = 53,
	Six = 54,
	Seven = 55,
	Eight = 56,
	Nine = 57,
	Semicolon = 59,
	Equals = 61,
	A = 65,
	B = 66,
	C = 67,
	D = 68,
	E = 69,
	F = 70,
	G = 71,
	H = 72,
	I = 73,
	J = 74,
	K = 75,
	L = 76,
	M = 77,
	N = 78,
	O = 79,
	P = 80,
	Q = 81,
	R = 82,
	S = 83,
	T = 84,
	U = 85,
	V = 86,
	W = 87,
	X = 88,
	Y = 89,
	Z = 90,
	LeftBracket = 91,
	Backslash = 92,
	RightBracket = 93,
	Grave = 96,
	Escape = 256,
	Return = 257,
	Tab = 258,
	Backspace = 259,
	Insert = 260,
	Delete = 261,
	Right = 262,
	Left = 263,
	Down = 264,
	Up = 265,
	PageUp = 266,
	PageDown = 267,
	Home = 268,
	End = 269,
	CapsLock = 280,
	ScrollLock = 281,
	NumLock = 282,
	PrintScreen = 283,
	Pause = 284,
	F1 = 290,
	F2 = 291,
	F3 = 292,
	F4 = 293,
	F5 = 294,
	F6 = 295,
	F7 = 296,
	F8 = 297,
	F9 = 298,
	F10 = 299,
	F11 = 300,
	F12 = 301,
	ZeroPad = 320,
	OnePad = 321,
	TwoPad = 322,
	ThreePad = 323,
	FourPad = 324,
	FivePad = 325,
	SixPad = 326,
	SevenPad = 327,
	EightPad = 328,
	NinePad = 329,
	Decimal = 330,
	Divide = 331,
	Multiply = 332,
	Subtract = 333,
	Add = 334,
	KeypadEnter = 335,
	KeypadEquals = 336,
	LeftShift = 340,
	LeftControl = 341,
	LeftAlt = 342,
	LeftSuper = 343,
	RightShift = 344,
	RightControl = 345,
	RightAlt = 346,
	RightSuper = 347,
	Apps = 348,
	ButtonX = 349,
	VolumeUp = 350,
	VolumeDown = 351,
}

GraphicsLevel :: enum {
	Automatic = 0,
	Compatibility = 1,
	Performance = 2,
	Low = 3,
	Medium = 4,
	High = 5,
	Ultra = 6,
}

MachineNetworkOwner :: enum {
	Server = 0,
	Client = 1,
}

NotificationAnchor :: enum {
	TopRight = 0,
	TopLeft = 1,
	BottomRight = 2,
	BottomLeft = 3,
}

NotificationState :: enum {
	Entering = 0,
	Visible = 1,
	Exiting = 2,
}

GamepadAxis :: enum {
	LeftX = 0,
	LeftY = 1,
	RightX = 2,
	RightY = 3,
	LeftTrigger = 4,
	RightTrigger = 5,
}

UserInputType :: enum {
	None = 0,
	MouseButton1 = 1,
	MouseButton2 = 2,
	MouseButton3 = 3,
	MouseWheel = 4,
	MouseMovement = 5,
	Keyboard = 6,
	Touch = 7,
	Gamepad1 = 8,
	Gamepad2 = 9,
	Gamepad3 = 10,
	Gamepad4 = 11,
	Gamepad5 = 12,
	Gamepad6 = 13,
	Gamepad7 = 14,
	Gamepad8 = 15,
	Accelerometer = 16,
	Gyro = 17,
	Gamepad = 18,
	TextInput = 19,
	Voice = 20,
}

PartType :: enum {
	Block = 0, // "block"
	Ball = 1, // "sphere"
	Cylinder = 2, // "cylinder"
	Wedge = 3, // "wedge"
	Torus = 4, // "torus"
	CornerWedge = 5, // "cornerwedge"
}

ActuatorRelativeTo :: enum {
	World = 0,
	Attachment0 = 1,
	Attachment1 = 2,
}

ForceLimitMode :: enum {
	Magnitude = 0,
	PerAxis = 1,
}

VelocityConstraintMode :: enum {
	Vector = 0,
	Line = 1,
	Plane = 2,
}

Material :: enum {
	SmoothPlastic = 0, // "smoothplastic"
	Wood = 1, // "wood"
	Brick = 2, // "brick"
	Grass = 3, // "grass"
	Concrete = 4, // "concrete"
	Slate = 5, // "slate"
	Glass = 6, // "glass"
	Neon = 7, // "neon"
	Sand = 8, // "sand"
	Water = 9, // "water"
	debug = 10, // "debug"
}

UserInputState :: enum {
	Begin = 0,
	Change = 1,
	End = 2,
	Cancel = 3,
	None = 4,
}

MouseButton :: enum {
	Left = 0,
	Right = 1,
	Middle = 2,
}

KinemiumMouseCursor :: enum {
	MOUSE_CURSOR_DEFAULT = 0,
	MOUSE_CURSOR_ARROW = 1,
	MOUSE_CURSOR_IBEAM = 2,
	MOUSE_CURSOR_CROSSHAIR = 3,
	MOUSE_CURSOR_POINTING_HAND = 4,
	MOUSE_CURSOR_RESIZE_EW = 5,
	MOUSE_CURSOR_RESIZE_NS = 6,
	MOUSE_CURSOR_RESIZE_NWSE = 7,
	MOUSE_CURSOR_RESIZE_NESW = 8,
	MOUSE_CURSOR_RESIZE_ALL = 9,
	MOUSE_CURSOR_NOT_ALLOWED = 10,
}

NormalId :: enum {
	Top = 1,
	Bottom = 2,
	Back = 3,
	Front = 4,
	Right = 5,
	Left = 6,
}

FontStyle :: enum {
	Normal = 0,
	Italic = 1,
}

MultiplayerMode :: enum {
	None = 0,
	Singleplayer = 1,
	Multiplayer = 2,
}

Language :: enum {
	Luau = 1,
}

PredictionMode :: enum {
	Off = 0,
	Automatic = 1,
	On = 2,
}

PredictionStatus :: enum {
	NotPredicted = 0,
	Predicted = 1,
}

AuthorityMode :: enum {
	Client = 0,
	Server = 1,
}

StepFrequency :: enum {
	Hz60 = 60,
	Hz120 = 120,
	Hz240 = 240,
}

TextXAlignment :: enum {
	Left = 0,
	Center = 1,
	Right = 2,
}

TextYAlignment :: enum {
	Top = 0,
	Center = 1,
	Bottom = 2,
}

TextTruncate :: enum {
	None = 0,
	Head = 1,
	Tail = 2,
	Line = 3,
	AtEnd = 1,
}

LeftRight :: enum {
	Left = 0,
	Center = 1,
	Right = 2,
}

TopBottom :: enum {
	Top = 0,
	Center = 1,
	Bottom = 2,
}

Dimension :: enum {
	_2D = 1,
	_3D = 2,
}

FillDirection :: enum {
	Vertical = 0,
	Horizontal = 1,
}

SortOrder :: enum {
	LayoutOrder = 0,
	Name = 1,
}

HorizontalAlignment :: enum {
	Left = 0,
	Center = 1,
	Right = 2,
}

VerticalAlignment :: enum {
	Top = 0,
	Center = 1,
	Bottom = 2,
}

ScreenInsets :: enum {
	None = 0,
	CoreUISafeInsets = 1,
	DeviceSafeInsets = 2,
	TopbarSafeInsets = 3,
}

ResamplerMode :: enum {
	Default = 0,
	Pixelated = 1,
}

ScrollBarInset :: enum {
	None = 0,
	ScrollBar = 1,
	Always = 2,
}

SelectionBehavior :: enum {
	Escape = 0,
	Stop = 1,
}

UIFlexMode :: enum {
	None = 0,
	Grow = 1,
	Shrink = 2,
	Fill = 3,
	Custom = 4,
}

ItemLineAlignment :: enum {
	Automatic = 0,
	Start = 1,
	Center = 2,
	End = 3,
	Stretch = 4,
}

Style :: enum {
	AlternatingSupports = 0,
	BridgeStyleSupports = 1,
	NoSupports = 2,
}

EasingStyle :: enum {
	Linear = 0,
	Sine = 1,
	Quad = 2,
	Cubic = 3,
	Quart = 4,
	Quint = 5,
	Expo = 6,
	Circular = 7,
	Back = 8,
	Bounce = 9,
	Elastic = 10,
	Smooth = 11,
	Smoother = 12,
	RidiculousWiggle = 13,
	RevBack = 14,
	Spring = 15,
	SoftSpring = 16,
}

EasingDirection :: enum {
	In = 0,
	Out = 1,
	InOut = 2,
}

CameraType :: enum {
	Custom = 0,
	Fixed = 1,
	Attach = 2,
	Watch = 3,
	Track = 4,
	Follow = 5,
	Scriptable = 6,
}

Axis :: enum {
	X = 0,
	Y = 1,
	Z = 2,
}

Face :: enum {
	Top = 0,
	Bottom = 1,
	Left = 2,
	Right = 3,
	Front = 4,
	Back = 5,
}

AutomaticSize :: enum {
	None = 0,
	X = 1,
	Y = 2,
	XY = 3,
}

PlaybackState :: enum {
	Stopped = 0,
	Playing = 1,
	Paused = 2,
}

AnimationPriority :: enum {
	Core = 0,
	Idle = 1,
	Movement = 2,
	Action = 3,
}

GameContext :: enum {
	Game = 1,
	Editor = 2,
	Home = 3,
}

RunContext :: enum {
	Legacy = 0,
	Server = 1,
	Client = 2,
	Plugin = 3,
	Editor = 4,
}

HumanoidStateType :: enum {
	None = 0,
	Running = 1,
	Jumping = 2,
	Freefall = 3,
	Landed = 4,
	Swimming = 5,
	Climbing = 6,
	Dead = 7,
	Seated = 8,
}

ZIndexBehavior :: enum {
	Global = 0,
	Sibling = 1,
}

ScaleType :: enum {
	Stretch = 0,
	Fit = 1,
	Crop = 2,
	Tile = 3,
	Slice = 4,
}

ConstraintType :: enum {
	Weld = 0,
	BallSocket = 1,
	Hinge = 2,
	Prismatic = 3,
	Spring = 4,
	Rope = 5,
}

SurfaceType :: enum {
	Smooth = 0,
	Studs = 1,
	Inlet = 2,
	Universal = 3,
}

CollisionGroup :: enum {
	Default = 0,
	Player = 1,
	World = 2,
	Sensor = 3,
}

BodyType2D :: enum {
	Static = 0,
	Kinematic = 1,
	Dynamic = 2,
}

ShapeType2D :: enum {
	Circle = 0,
	Box = 1,
	Polygon = 2,
	Edge = 3,
	Chain = 4,
}

PhysicsEngine :: enum {
	Default = 0,
	Jolt = 1,
	Ode = 2,
	Bullet = 3,
	PhysX = 4,
	Impulse3D = 6,
}

JointType2D :: enum {
	Revolute = 0,
	Prismatic = 1,
	Distance = 2,
	Pulley = 3,
	Mouse = 4,
	Gear = 5,
	Wheel = 6,
	Weld = 7,
	Friction = 8,
	Motor = 9,
}

RaycastMode2D :: enum {
	Closest = 0,
	Any = 1,
	All = 2,
}

CollisionDetection2D :: enum {
	Discrete = 0,
	Continuous = 1,
}

ContactState2D :: enum {
	Begin = 0,
	Persist = 1,
	End = 2,
}

BodySleepState2D :: enum {
	Awake = 0,
	Sleeping = 1,
}

RigidbodyConstraints2D :: enum {
	None = 0,
	FreezePositionX = 1,
	FreezePositionY = 2,
	FreezeRotation = 4,
	FreezeAll = 7,
}

ForceMode2D :: enum {
	Force = 0,
	Impulse = 1,
}

PhysicsMaterialCombine :: enum {
	Average = 0,
	Min = 1,
	Multiply = 2,
	Max = 3,
}

RenderFidelity :: enum {
	Automatic = 0,
	Precise = 1,
	Performance = 2,
}

CollisionFidelity :: enum {
	Default = 0,
	Hull = 1,
	Box = 2,
	PreciseConvexDecomposition = 3,
}

AudioBackend :: enum {
	RAUDIO = 0,
	MiniAudio = 1,
}

CameraType :: enum {
	Custom = 0,
	Scriptable = 1,
	Orbital = 2,
	FirstPerson = 3,
	ThirdPerson = 4,
	Follow = 5,
	Shoulder = 8,
	TopDown = 9,
	Isometric = 10,
}

ReplicationMode :: enum {
	Automatic = 0,
	ServerOnly = 1,
	OwnerOnly = 2,
	Manual = 3,
	Never = 4,
}

NetworkReliability :: enum {
	ReliableOrdered = 0,
	ReliableUnordered = 1,
	Unreliable = 2,
	UnreliableSequenced = 3,
}

SecurityCapabilities :: enum {
	UserScript = 1,
	Internals = 2,
}

TouchMovementMode :: enum {
	Default = 0,
	Thumbstick = 1,
	DPad = 2,
	Thumbpad = 3,
	ClickToMove = 4,
	DynamicThumbstick = 5,
}

TrackerError :: enum {
	Ok = 0,
	NoService = 1,
	InitFailed = 2,
	NoVideo = 3,
	VideoError = 4,
	VideoNoPermission = 5,
	VideoUnsupported = 6,
	NoAudio = 7,
	AudioError = 8,
	AudioNoPermission = 9,
	UnsupportedDevice = 10,
}

TrackerExtrapolationFlagMode :: enum {
	Auto = 3,
	ForceDisabled = 0,
	ExtrapolateFacsAndPose = 1,
	ExtrapolateFacsOnly = 2,
}

TrackerFaceTrackingStatus :: enum {
	FaceTrackingSuccess = 0,
	FaceTrackingNoFaceFound = 1,
	FaceTrackingUnknown = 2,
	FaceTrackingLost = 3,
	FaceTrackingHasTrackingError = 4,
	FaceTrackingIsOccluded = 5,
	FaceTrackingUninitialized = 6,
}

TrackerLodFlagMode :: enum {
	Auto = 2,
	ForceFalse = 0,
	ForceTrue = 1,
}

TrackerLodValueMode :: enum {
	Auto = 2,
	Force0 = 0,
	Force1 = 1,
}

TrackerMode :: enum {
	None = 0,
	Audio = 1,
	Video = 2,
	AudioVideo = 3,
}

TrackerPromptEvent :: enum {
	LODCameraRecommendDisable = 0,
}

TrackerType :: enum {
	None = 0,
	Face = 1,
	UpperBody = 2,
}

TriStateBoolean :: enum {
	False = 2,
	True = 1,
	Unknown = 0,
}

TweenStatus :: enum {
	Canceled = 0,
	Completed = 1,
}

UICaptureMode :: enum {
	All = 0,
	None = 1,
}

UIDragDetectorBoundingBehavior :: enum {
	Automatic = 0,
	EntireObject = 1,
	HitPoint = 2,
}

UIDragDetectorDragRelativity :: enum {
	Absolute = 0,
	Relative = 1,
}

UIDragDetectorDragSpace :: enum {
	Parent = 0,
	LayerCollector = 1,
	Reference = 2,
}

UIDragDetectorDragStyle :: enum {
	TranslatePlane = 0,
	TranslateLine = 1,
	Rotate = 2,
	Scriptable = 3,
}

UIDragDetectorResponseStyle :: enum {
	Offset = 0,
	Scale = 1,
	CustomOffset = 2,
	CustomScale = 3,
}

UIDragSpeedAxisMapping :: enum {
	XY = 0,
	XX = 1,
	YY = 2,
}

UIFlexAlignment :: enum {
	None = 0,
	Fill = 1,
	SpaceAround = 2,
	SpaceBetween = 3,
	SpaceEvenly = 4,
}

UIFlexMode :: enum {
	None = 0,
	Grow = 1,
	Shrink = 2,
	Fill = 3,
	Custom = 4,
}

UITheme :: enum {
	Light = 0,
	Dark = 1,
}

UiMessageType :: enum {
	UiMessageError = 0,
	UiMessageInfo = 1,
}

UpdateState :: enum {
	UpdateNotAvailable = 0,
	UpdateAvailable = 1,
	UpdateInProgress = 2,
	UpdateReady = 3,
	UpdateFailed = 4,
}

UploadCaptureResult :: enum {
	Success = 0,
	NeedPermission = 1,
	CaptureModerated = 2,
	CaptureNotInGallery = 3,
	IneligibleCapture = 4,
	UploadQuotaReached = 5,
}

UsageContext :: enum {
	Default = 0,
	Preview = 1,
}

UserCFrame :: enum {
	Head = 0,
	LeftHand = 1,
	RightHand = 2,
	Floor = 3,
}

UserInputState :: enum {
	Begin = 0,
	Change = 1,
	End = 2,
	Cancel = 3,
	None = 4,
}

UserInputType :: enum {
	MouseButton1 = 0,
	MouseButton2 = 1,
	MouseButton3 = 2,
	MouseWheel = 3,
	MouseMovement = 4,
	Touch = 7,
	Keyboard = 8,
	Focus = 9,
	Accelerometer = 10,
	Gyro = 11,
	Gamepad1 = 12,
	Gamepad2 = 13,
	Gamepad3 = 14,
	Gamepad4 = 15,
	Gamepad5 = 16,
	Gamepad6 = 17,
	Gamepad7 = 18,
	Gamepad8 = 19,
	TextInput = 20,
	InputMethod = 21,
	None = 22,
}

VRComfortSetting :: enum {
	Comfort = 0,
	Normal = 1,
	Expert = 2,
	Custom = 3,
}

VRControllerModelMode :: enum {
	Disabled = 0,
	Transparent = 1,
}

VRDeviceType :: enum {
	Unknown = 0,
	OculusRift = 1,
	HTCVive = 2,
	ValveIndex = 3,
	OculusQuest = 4,
}

VRLaserPointerMode :: enum {
	Disabled = 0,
	Pointer = 1,
	DualPointer = 2,
}

VRSafetyBubbleMode :: enum {
	NoOne = 0,
	OnlyFriends = 1,
	Anyone = 2,
}

VRScaling :: enum {
	World = 0,
	Off = 1,
}

VRSessionState :: enum {
	Undefined = 0,
	Idle = 1,
	Visible = 2,
	Focused = 3,
	Stopping = 4,
}

VRTouchpad :: enum {
	Left = 0,
	Right = 1,
}

VRTouchpadMode :: enum {
	Touch = 0,
	VirtualThumbstick = 1,
	ABXY = 2,
}

VelocityConstraintMode :: enum {
	Line = 0,
	Plane = 1,
	Vector = 2,
}

VerticalAlignment :: enum {
	Center = 0,
	Top = 1,
	Bottom = 2,
}

VerticalScrollBarPosition :: enum {
	Right = 0,
	Left = 1,
}

VibrationMotor :: enum {
	Large = 0,
	Small = 1,
	LeftTrigger = 2,
	RightTrigger = 3,
	LeftHand = 4,
	RightHand = 5,
}

VideoCaptureResult :: enum {
	Success = 0,
	OtherError = 1,
	ScreenSizeChanged = 2,
	TimeLimitReached = 3,
}

VideoCaptureStartedResult :: enum {
	Success = 0,
	OtherError = 1,
	CapturingAlready = 2,
	NoDeviceSupport = 3,
	NoSpaceOnDevice = 4,
}

VideoDeviceCaptureQuality :: enum {
	Default = 0,
	Low = 1,
	Medium = 2,
	High = 3,
}

VideoError :: enum {
	Ok = 0,
	Eof = 1,
	EAgain = 2,
	BadParameter = 3,
	AllocFailed = 4,
	CodecInitFailed = 5,
	CodecCloseFailed = 6,
	DecodeFailed = 7,
	ParsingFailed = 8,
	Unsupported = 9,
	Generic = 10,
	DownloadFailed = 11,
	StreamNotFound = 12,
	EncodeFailed = 13,
	CreateFailed = 14,
	NoPermission = 15,
	NoService = 16,
	ReleaseFailed = 17,
	Unknown = 18,
}

VideoSampleSize :: enum {
	Small = 0,
	Medium = 1,
	Large = 2,
	Full = 3,
}

ViewMode :: enum {
	None = 0,
	GeometryComplexity = 1,
	Transparent = 2,
	Decal = 3,
}

VirtualCursorMode :: enum {
	Default = 0,
	Disabled = 1,
	Enabled = 2,
}

VirtualInputMode :: enum {
	None = 0,
	Recording = 1,
	Playing = 2,
}

VoiceChatDistanceAttenuationType :: enum {
	Inverse = 0,
	Legacy = 1,
}

VoiceChatState :: enum {
	Idle = 0,
	Joining = 1,
	JoiningRetry = 2,
	Joined = 3,
	Leaving = 4,
	Ended = 5,
	Failed = 6,
}

VoiceClientLeaveReasons :: enum {
	Unknown = 0,
	ClientNetworkDisconnected = 1,
	PlayerLeft = 2,
	ClientShutdown = 3,
	PublishFailed = 4,
	RejoinReceived = 5,
	VoiceReboot = 6,
	ImguiDebugLeave = 7,
	LuaInitiated = 8,
}

VoiceControlPath :: enum {
	Publish = 0,
	Subscribe = 1,
	Join = 2,
}

VolumetricAudio :: enum {
	Disabled = 0,
	Automatic = 1,
	Enabled = 2,
}

WaterDirection :: enum {
	NegX = 0,
	X = 1,
	NegY = 2,
	Y = 3,
	NegZ = 4,
	Z = 5,
}

WaterForce :: enum {
	None = 0,
	Small = 1,
	Medium = 2,
	Strong = 3,
	Max = 4,
}

WebSocketState :: enum {
	Connecting = 0,
	Open = 1,
	Closing = 2,
	Closed = 3,
}

WebStreamClientState :: enum {
	Connecting = 0,
	Open = 1,
	Error = 2,
	Closed = 3,
}

WebStreamClientType :: enum {
	SSE = 0,
	RawStream = 1,
	WebSocket = 2,
}

WeldConstraintPreserve :: enum {
	All = 0,
	None = 1,
	Touching = 2,
}

WhisperChatPrivacyMode :: enum {
	AllUsers = 0,
	NoOne = 1,
}

WrapLayerAutoSkin :: enum {
	Disabled = 0,
	EnabledPreserve = 1,
	EnabledOverride = 2,
}

WrapLayerDebugMode :: enum {
	None = 0,
	BoundCage = 1,
	LayerCage = 2,
	BoundCageAndLinks = 3,
	Reference = 4,
	Rbf = 5,
	OuterCage = 6,
	ReferenceMeshAfterMorph = 7,
	HSROuterDetail = 8,
	HSROuter = 9,
	HSRInner = 10,
	HSRInnerReverse = 11,
	LayerCageFittedToBase = 12,
	LayerCageFittedToPrev = 13,
	PreWrapDeformerOuterCage = 14,
}

WrapTargetDebugMode :: enum {
	None = 0,
	TargetCageOriginal = 1,
	TargetCageCompressed = 2,
	TargetCageInterface = 3,
	TargetLayerCageOriginal = 4,
	TargetLayerCageCompressed = 5,
	TargetLayerInterface = 6,
	Rbf = 7,
	OuterCageDetail = 8,
	PreWrapDeformerCage = 9,
}

ZIndexBehavior :: enum {
	Global = 0,
	Sibling = 1,
}
