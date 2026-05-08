#import "../Defines.h"
#import "CLDonateController.h"
#include <objc/runtime.h>

#define TEXT_SECTION 0
#define PATREON_SECTION 1
#define BITCOIN_SECTION 2
#define BITCOIN_ADDRESS @"177JwbKv8msAQPVk8azEKMCuNBWHJbs1XT"
#define PATREON_URL @"https://www.patreon.com/user?u=20478714"

@interface UITableView (Private)
- (NSArray *) indexPathsForSelectedRows;
@property(nonatomic) BOOL allowsMultipleSelectionDuringEditing;
@end

@implementation CLDonateController

- (instancetype)init
{
	if (self = [super init])
    {
		_tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height) style:UITableViewStyleGrouped];
		[_tableView setDataSource:self];
		[_tableView setDelegate:self];
		
		if ([self respondsToSelector:@selector(setView:)])
			[self performSelectorOnMainThread:@selector(setView:) withObject:_tableView waitUntilDone:YES];

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0,0,10,10)];
        titleLabel.font = [UIFont boldSystemFontOfSize:17];
        titleLabel.text = @"Donate";
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.navigationItem.titleView = [UIView new];
        [self.navigationItem.titleView addSubview:titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:self.navigationItem.titleView.topAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.navigationItem.titleView.leadingAnchor],
            [titleLabel.trailingAnchor constraintEqualToAnchor:self.navigationItem.titleView.trailingAnchor],
            [titleLabel.bottomAnchor constraintEqualToAnchor:self.navigationItem.titleView.bottomAnchor],
        ]];

        NSError *sessionError = nil;
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:&sessionError];
        [[AVAudioSession sharedInstance] setActive:true error:&sessionError];

        NSError *error;
        _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL URLWithString:BUNDLE_PATH "iloveyou.mp3"] error:&error];
        if(!error)
        {
            [_player prepareToPlay];
        }
	}
	return self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)dealloc
{
    [_player stop];
}

- (id)view
{
    return _tableView;
}

/* UITableViewDelegate / UITableViewDataSource Methods {{{ */
- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (id) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch(section)
    {
        case BITCOIN_SECTION:
            return @"Bitcoin (tap to copy address)";
        case PATREON_SECTION:
            return @"Patreon";
    }
    return nil;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

-(id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"yeah"];
    if(!cell)
    {
        cell = [UITableViewCell.alloc initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"EffectCell"];
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }
    //cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    switch(indexPath.section)
    {
        case TEXT_SECTION:
            cell.textLabel.text = [NSString stringWithFormat:@"%@%@%@", @"\u2764\u2764\u2764\u2764 ", LOCALIZE(@"THANK_YOU", @"Thank you"), @" \u2764\u2764\u2764\u2764"];
        break;
        case BITCOIN_SECTION:
            cell.textLabel.text = BITCOIN_ADDRESS;
        break;
        case PATREON_SECTION:
            cell.textLabel.text = LOCALIZE(@"PAYPAL", @"Tap here to go to Safari and donate to via Patreon");
        break;
    }
    return cell;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:true];
    if(indexPath.section == BITCOIN_SECTION)
    {
        UIPasteboard.generalPasteboard.string = BITCOIN_ADDRESS;

        UIAlertController * alert = [UIAlertController alertControllerWithTitle:@"Address copied!" message:nil preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* okayButton = [UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {}];
        [alert addAction:okayButton];
        [self presentViewController:alert animated:YES completion:nil];

    }
    else if(indexPath.section == PATREON_SECTION)
    {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:PATREON_URL] options:@{} completionHandler:nil];
    }
    else
    {
        _player.currentTime = 0;
        [_player prepareToPlay];
        [_player play];
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView*)tableView editingStyleForRowAtIndexPath:(NSIndexPath*)indexPath
{
    return UITableViewCellEditingStyleNone;
}

@end
