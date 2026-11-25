// Jembatan Now Playing untuk Bilah.
//
// Sejak macOS 15.4, MediaRemote hanya melayani proses milik Apple. Pustaka ini dimuat oleh /usr/bin/perl
// (program bawaan Apple), lalu:
//   - menulis satu baris JSON ke stdout setiap info Now Playing berubah (plus detak tiap 5 detik),
//   - membaca perintah dari stdin: toggle, play, pause, next, previous, refresh.
// Saat Bilah ditutup, pipa stdin tertutup dan proses ini ikut keluar.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <pthread.h>

typedef void (*MRGetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetPID)(dispatch_queue_t, void (^)(int));
typedef void (*MRGetPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClient)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*MRClientString)(id);
typedef void (*MRRegister)(dispatch_queue_t);
typedef Boolean (*MRSend)(int, CFDictionaryRef);

static void *gLib;
static MRGetInfo gInfo;
static MRGetPID gPID;
static MRGetPlaying gPlaying;
static MRGetClient gClient;
static MRClientString gClientBundle;
static MRClientString gClientParent;
static MRSend gSend;
static BOOL gEmitScheduled;

static void writeJSON(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *appNameForBundle(NSString *bundleID) {
    NSURL *url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleID];
    if (!url) return nil;
    return [[[NSFileManager defaultManager] displayNameAtPath:url.path] stringByDeletingPathExtension];
}

static void emit(void) {
    __block NSDictionary *info = nil;
    __block int pid = 0;
    __block BOOL playing = NO;
    __block NSString *clientBundle = nil;
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    dispatch_group_enter(group);
    gInfo(queue, ^(CFDictionaryRef d) {
        info = d ? [(__bridge NSDictionary *)d copy] : nil;
        dispatch_group_leave(group);
    });
    dispatch_group_enter(group);
    gPID(queue, ^(int p) {
        pid = p;
        dispatch_group_leave(group);
    });
    dispatch_group_enter(group);
    gPlaying(queue, ^(Boolean b) {
        playing = b;
        dispatch_group_leave(group);
    });
    if (gClient && gClientBundle) {
        dispatch_group_enter(group);
        gClient(queue, ^(id client) {
            if (client) {
                // Browser memutar lewat proses pembantu; pakai aplikasi induknya (mis. Safari) kalau ada.
                CFStringRef parent = gClientParent ? gClientParent(client) : NULL;
                CFStringRef own = gClientBundle(client);
                clientBundle = [(__bridge NSString *)(parent ?: own) copy];
            }
            dispatch_group_leave(group);
        });
    }
    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));

    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"playing"] = @(playing);
    NSString *bundle = clientBundle;
    if (!bundle && pid > 0) bundle = [NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier;
    if (bundle) {
        out[@"bundle"] = bundle;
        NSString *name = appNameForBundle(bundle);
        if (name) out[@"app"] = name;
    }
    NSDictionary<NSString *, NSString *> *strings = @{
        @"title": @"kMRMediaRemoteNowPlayingInfoTitle",
        @"artist": @"kMRMediaRemoteNowPlayingInfoArtist",
        @"album": @"kMRMediaRemoteNowPlayingInfoAlbum",
    };
    for (NSString *key in strings) {
        id v = info[strings[key]];
        if ([v isKindOfClass:[NSString class]]) out[key] = v;
    }
    NSDictionary<NSString *, NSString *> *numbers = @{
        @"duration": @"kMRMediaRemoteNowPlayingInfoDuration",
        @"elapsed": @"kMRMediaRemoteNowPlayingInfoElapsedTime",
        @"rate": @"kMRMediaRemoteNowPlayingInfoPlaybackRate",
    };
    for (NSString *key in numbers) {
        id v = info[numbers[key]];
        if ([v isKindOfClass:[NSNumber class]]) out[key] = v;
    }
    id stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    if ([stamp isKindOfClass:[NSDate class]]) out[@"timestamp"] = @([(NSDate *)stamp timeIntervalSince1970]);
    writeJSON(out);
}

static void scheduleEmit(void) {
    if (gEmitScheduled) return;
    gEmitScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gEmitScheduled = NO;
        emit();
    });
}

static void *readCommands(void *unused) {
    char line[256];
    while (fgets(line, sizeof line, stdin)) {
        int command = -1;
        if (!strncmp(line, "play", 4)) command = 0;
        else if (!strncmp(line, "pause", 5)) command = 1;
        else if (!strncmp(line, "toggle", 6)) command = 2;
        else if (!strncmp(line, "next", 4)) command = 4;
        else if (!strncmp(line, "previous", 8)) command = 5;
        if (command >= 0) gSend(command, NULL);
        dispatch_async(dispatch_get_main_queue(), ^{ scheduleEmit(); });
    }
    exit(0); // Bilah menutup pipa: selesai.
    return NULL;
}

static NSString *constant(const char *name) {
    CFStringRef *p = (CFStringRef *)dlsym(gLib, name);
    return p ? (__bridge NSString *)*p : [NSString stringWithUTF8String:name];
}

// Dipanggil perl lewat DynaLoader::dl_install_xsub; argumen perl diabaikan.
void bilah_mediaremote_main(void) {
    @autoreleasepool {
        gLib = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        gInfo = (MRGetInfo)dlsym(gLib, "MRMediaRemoteGetNowPlayingInfo");
        gPID = (MRGetPID)dlsym(gLib, "MRMediaRemoteGetNowPlayingApplicationPID");
        gPlaying = (MRGetPlaying)dlsym(gLib, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        gClient = (MRGetClient)dlsym(gLib, "MRMediaRemoteGetNowPlayingClient");
        gClientBundle = (MRClientString)dlsym(gLib, "MRNowPlayingClientGetBundleIdentifier");
        gClientParent = (MRClientString)dlsym(gLib, "MRNowPlayingClientGetParentAppBundleIdentifier");
        gSend = (MRSend)dlsym(gLib, "MRMediaRemoteSendCommand");
        MRRegister registerNotifications = (MRRegister)dlsym(gLib, "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (!gInfo || !gPID || !gPlaying || !gSend || !registerNotifications) {
            writeJSON(@{@"error": @"MediaRemote tidak tersedia"});
            exit(1);
        }

        registerNotifications(dispatch_get_main_queue());
        const char *names[] = {
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
        };
        for (int i = 0; i < 4; i++) {
            [[NSNotificationCenter defaultCenter] addObserverForName:constant(names[i]) object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *n) { scheduleEmit(); }];
        }
        emit();

        pthread_t thread;
        pthread_create(&thread, NULL, readCommands, NULL);
        [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *t) { emit(); }];
        CFRunLoopRun();
    }
}
