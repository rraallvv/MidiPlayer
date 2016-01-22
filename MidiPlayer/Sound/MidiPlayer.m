#import "MidiPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

@implementation MidiPlayer

BOOL released = YES;
BOOL stopped = YES;
BOOL paused = NO;

- (void) loadMIDI: (NSString*)path programs: (NSArray*)programs;
{
	//NSLog(@"Setup");
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		//NSLog(@"Setup background");
		if (path != nil && [path length] > 0 && programs != nil && [programs count] > 0) {
			BOOL success = [self setupPlayer:path withInstruments:programs];
			if (success) {
				released = NO;
				stopped = YES;
				paused = NO;

				[self playerLoop];
			} else {
			}
		} else {
		}
	});
}

- (void)play
{
	//NSLog(@"Play %i", released);
	if (ms == nil || released || !(stopped || paused)) {
	} else {
		MusicPlayerStart(mp);
		stopped = NO;
		paused = NO;
	}
}

- (void)stop
{
	if (ms == nil || stopped || released) {
	} else {
		MusicPlayerStop(mp);
		[self setTime: 0];

		stopped = YES;
		paused = NO;
	}
}

- (void)pause
{
	if (ms == nil || paused || stopped || released) {
	} else {
		MusicPlayerStop(mp);
		stopped = NO;
		paused = YES;
	}
}

- (void)getCurrentPosition
{
	if (ms == nil || released) {
	} else {
		Float64 time = [self getTime];
		// Don't return more than track length
		if (time > longestTrackLength) {
			time = longestTrackLength;
		}
	}
}

- (Float64)getTime
{
	MusicTimeStamp beats = 0;
	MusicPlayerGetTime (mp, &beats);
	Float64 time;
	MusicSequenceGetSecondsForBeats(ms, beats, &time);
	//NSLog(@"GetTime: %f", time);
	return time;
}

- (void)seekTo:(Float64)time {
	if (released) {
		return;
	}
	time = time / 1000;
	//NSLog(@"SetTime: %f", time);
	[self setTime:time];
}

- (void)setTime:(Float64)time {
	MusicTimeStamp beats = 0;
	MusicSequenceGetBeatsForSeconds(ms, time, &beats);
	MusicPlayerSetTime(mp, beats);
}

- (void)dealloc
{
	if (ms == nil || released) {
	} else {
		if (!(stopped && paused)) {
			MusicPlayerStop(mp);
		}
		DisposeMusicSequence(ms);
		released = true;
		//NSLog(@"DoRelease");
	}
}


- (BOOL)setupPlayer:(NSString*)path withInstruments:(NSArray*)programs {
	// Initialise the music sequence
	NewMusicSequence(&ms);

	NSURL * midiFileURL;
	NSArray *pathArray = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask,YES);
	NSString *documentsDirectory = [pathArray objectAtIndex:0];
	NSString *midiPath = [documentsDirectory stringByAppendingPathComponent:path];

	if ([[NSFileManager defaultManager] fileExistsAtPath:midiPath])
	{
		midiFileURL = [NSURL fileURLWithPath:midiPath isDirectory:NO];
	} else {
		midiFileURL = [NSURL URLWithString:[[NSBundle mainBundle] pathForResource:path ofType:nil]];
		if (midiFileURL == nil) {
			return NO;
		}
	}

	MusicSequenceFileLoad(ms, (__bridge CFURLRef)(midiFileURL), 0, kMusicSequenceLoadSMF_ChannelsToTracks);
	//MusicSequenceFileLoad(ms, (__bridge CFURLRef)(midiFileURL), 0, 0);

	[self setupGraph:programs];
	[self assignInstrumentsToTracks:programs];

	NewMusicPlayer(&mp);

	// Load the sequence into the music player
	MusicPlayerSetSequence(mp, ms);

	MusicPlayerPreroll(mp);

	[self setLongestTrackLength];

	return YES;
}

- (void)setLongestTrackLength {
	UInt32 trackCount;
	MusicSequenceGetTrackCount(ms, &trackCount);

	MusicTimeStamp longest = 0;
	for (int i = 0; i < trackCount; i++) {
		MusicTrack t;
		MusicSequenceGetIndTrack(ms, i, &t);

		MusicTimeStamp len;
		UInt32 sz = sizeof(MusicTimeStamp);
		MusicTrackGetProperty(t, kSequenceTrackProperty_TrackLength, &len, &sz);
		if (len > longest) {
			longest = len;
		}
	}
	Float64 longestTime;
	MusicSequenceGetSecondsForBeats(ms, longest, &longestTime);
	longestTrackBeats = longest;
	longestTrackLength = longestTime;
}

- (void)playerLoop {
	BOOL lastStopped = stopped;
	BOOL lastPaused = paused;
	while (!released) {
		if (stopped) {
			//NSLog(@"isStopped, lastStopped:%i", lastStopped);
			if (!lastStopped) {
				// Was just stopped
				//NSLog(@"Stopped");
				lastStopped = stopped;
				released = YES;
			}
		} else if (paused) {
			//NSLog(@"isPaused");
			if (!lastPaused) {
				//NSLog(@"Paused");
				// Was just paused
				lastPaused = paused;
			}
		} else {
			// Running
			//NSLog(@"NowRunning");
			if ([self getTime] >= longestTrackLength) {
				// Track reached end
				//NSLog(@"Ended");
				stopped = YES;
				released = YES;
				lastStopped = YES;
				paused = NO;
				lastPaused = NO;
				MusicPlayerStop(mp);
				[self setTime: 0];
			} else if (lastPaused || lastStopped) {
				// Just started running
				//NSLog(@"Running");
				lastPaused = NO;
				lastStopped = NO;
			}
		}
		[NSThread sleepForTimeInterval:.01];
	}
	//NSLog(@"Released");
	stopped = YES;
	paused = NO;
}

- (void)setupGraph:(NSArray*)programs {
	NewAUGraph (&_processingGraph);
	AUNode samplerNodes[[programs count]];
	AUNode ioNode, mixerNode;
	AudioUnit samplerUnits[[programs count]];
	AudioUnit ioUnit, mixerUnit;

	AudioComponentDescription cd = {};
	cd.componentManufacturer	 = kAudioUnitManufacturer_Apple;

	//----------------------------------------
	// 1. Add the Sampler unit nodes to the graph
	//----------------------------------------
	cd.componentType = kAudioUnitType_MusicDevice;
	cd.componentSubType = kAudioUnitSubType_Sampler;

	for (NSInteger i = 0; i < [programs count]; i++) {
		AUNode node;
		AUGraphAddNode (self.processingGraph, &cd, &node);
		samplerNodes[i] = node;
	}

	//-----------------------------------
	// 2. Add a Mixer unit node to the graph
	//-----------------------------------
	cd.componentType		  = kAudioUnitType_Mixer;
	cd.componentSubType	   = kAudioUnitSubType_MultiChannelMixer;

	AUGraphAddNode (self.processingGraph, &cd, &mixerNode);

	//--------------------------------------
	// 3. Add the Output unit node to the graph
	//--------------------------------------
	cd.componentType = kAudioUnitType_Output;
	cd.componentSubType = kAudioUnitSubType_RemoteIO;  // Output to speakers

	AUGraphAddNode (self.processingGraph, &cd, &ioNode);

	//---------------
	// Open the graph
	//---------------
	AUGraphOpen (self.processingGraph);

	//-----------------------------------------------------------
	// Obtain the mixer unit instance from its corresponding node
	//-----------------------------------------------------------
	AUGraphNodeInfo (
					 self.processingGraph,
					 mixerNode,
					 NULL,
					 &mixerUnit
					 );

	//--------------------------------
	// Set the bus count for the mixer
	//--------------------------------
	UInt32 numBuses = 3;
	AudioUnitSetProperty(mixerUnit,
						 kAudioUnitProperty_ElementCount,
						 kAudioUnitScope_Input,
						 0,
						 &numBuses,
						 sizeof(numBuses));



	//------------------
	// Connect the nodes
	//------------------
	for (NSInteger i = 0; i < [programs count]; i++) {
		AUGraphConnectNodeInput (self.processingGraph, samplerNodes[i], 0, mixerNode, (unsigned int)i);
	}

	// Connect the mixer unit to the output unit
	AUGraphConnectNodeInput (self.processingGraph, mixerNode, 0, ioNode, 0);

	// Obtain references to all of the audio units from their nodes
	for (NSInteger i = 0; i < [programs count]; i++) {
		AUGraphNodeInfo (self.processingGraph, samplerNodes[i], 0, &samplerUnits[i]);
	}

	AUGraphNodeInfo (self.processingGraph, ioNode, 0, &ioUnit);

	MusicSequenceSetAUGraph(ms, self.processingGraph);

	// Set the instruments
	NSURL * bankURL;

	NSString *bankPath = [[NSBundle mainBundle] pathForResource:@"sounds" ofType:@"sf2"];

	if ([[NSFileManager defaultManager] fileExistsAtPath:bankPath])
	{
		bankURL = [NSURL fileURLWithPath:bankPath isDirectory:NO];
	} else {
		return;
	}


	for (NSInteger i = 0; i < [programs count]; i++) {
		AUSamplerBankPresetData bpdata;
		bpdata.bankURL  = (__bridge CFURLRef) bankURL;
		bpdata.bankMSB  = kAUSampler_DefaultMelodicBankMSB;
		bpdata.bankLSB  = kAUSampler_DefaultBankLSB;
		bpdata.presetID = (UInt8) [programs[i] intValue];

		AudioUnitSetProperty(samplerUnits[i],
							 kAUSamplerProperty_LoadPresetFromBank,
							 kAudioUnitScope_Global,
							 0,
							 &bpdata,
							 sizeof(bpdata));

		NSDictionary *classData;

		UInt32 size = sizeof(CFPropertyListRef);
		AudioUnitGetProperty(samplerUnits[i],
							 kAudioUnitProperty_ClassInfo,
							 kAudioUnitScope_Global,
							 0,
							 &classData,
							 &size);

		NSLog(@"Instrument loaded '%@'", [[classData valueForKey:@"Instrument"] valueForKey:@"name"]);
	}
}

- (void)assignInstrumentsToTracks:(NSArray*)programs {
	//-------------------------------------------------
	// Set the AUSampler nodes to be used by each track
	//-------------------------------------------------
	MusicTrack tracks[[programs count]];

	for (NSInteger i = 0; i < [programs count]; i++) {
		MusicTrack track;
		MusicSequenceGetIndTrack(ms, (unsigned int)i, &track);
		tracks[i] = track;
	}

	AUNode nodes[[programs count]];
	for (NSInteger i = 0; i < [programs count]; i++) {
		AUNode node;
		AUGraphGetIndNode (self.processingGraph, (unsigned int)i, &node);
		nodes[i] = node;
	}

	for (NSInteger i = 0; i < [programs count]; i++) {
		MusicTrackSetDestNode(tracks[i], nodes[i]);
	}
}

@end