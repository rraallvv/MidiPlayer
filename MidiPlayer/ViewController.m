#import "ViewController.h"
#include "Sound/MidiPlayer.h"

@implementation ViewController {
	MidiPlayer *player;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.

	player = [[MidiPlayer alloc] init];
	[player loadMIDI:@"demo.mid" programs:[NSArray arrayWithObjects:@0, @5, @7, @8, nil]];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

- (IBAction)play:(id)sender {
	[player play];
}

- (IBAction)pause:(id)sender {
	[player pause];
}

@end
