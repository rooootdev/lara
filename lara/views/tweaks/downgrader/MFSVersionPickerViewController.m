#import "MFSVersionPickerViewController.h"

@interface MFSVersionPickerViewController ()
@property (nonatomic, strong) NSArray* versions;
@end

@implementation MFSVersionPickerViewController

- (instancetype)initWithVersions:(NSArray*)versions completion:(MFSVersionPickerCompletion)completion
{
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self)
	{
		_versions = versions;
		_completionHandler = completion;
	}
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = @"Select Version";
	[self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"VersionCell"];
	UIBarButtonItem* cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
	self.navigationItem.leftBarButtonItem = cancelButton;
}

- (void)cancelTapped
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	return self.versions.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
	UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"VersionCell" forIndexPath:indexPath];
	NSDictionary* version = self.versions[indexPath.row];
	cell.textLabel.text = version[@"bundle_version"];
	cell.textLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary* selected = self.versions[indexPath.row];
	[self dismissViewControllerAnimated:YES completion:^
	{
		if (self.completionHandler)
		{
			self.completionHandler(selected);
		}
	}];
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
	return [NSString stringWithFormat:@"%lu versions available", (unsigned long)self.versions.count];
}

@end
