#import <Preferences/PSViewController.h>
#import <AVFoundation/AVFoundation.h>

@interface CLDonateController : PSViewController <UITableViewDelegate, UITableViewDataSource>
{
    UITableView *_tableView;
    AVAudioPlayer *_player;
}
// -(id)initForContentSize:(CGSize)size;
-(id)view;
@end 
