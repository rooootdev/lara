#import <Preferences/PSViewController.h>
#import "CLEffect.h"

@interface CLEffectsController : PSViewController <UITableViewDelegate, UITableViewDataSource> {
	UITableView *_tableView;
    BOOL _initialized;
}
@property (nonatomic, retain) NSMutableArray *effects;
@property (nonatomic, retain) NSMutableArray *selectedEffects;
@property (nonatomic, retain) UILabel *titleLabel;
// + (void)load;
- (id)view;
- (void)refreshList;
@end 
