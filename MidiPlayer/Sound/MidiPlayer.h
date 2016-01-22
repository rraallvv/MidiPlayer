#import <AudioToolbox/AudioToolbox.h>
@interface MidiPlayer : NSObject {
	MusicPlayer mp;
	MusicSequence ms;
	Float64 longestTrackLength;
	MusicTimeStamp longestTrackBeats;

	BOOL released;
	BOOL stopped;
	BOOL paused;
}

@property (readwrite) AUGraph processingGraph;

- (void) loadMIDI: (NSString*)path programs: (NSArray*)programs;
- (void) play;
- (void) pause;

@end