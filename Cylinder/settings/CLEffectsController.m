#import "../Defines.h"
#import "CLEffectsController.h"
#import "CylinderSettings.h"

#import "CLAlignedTableViewCell.h"

static CLEffectsController *sharedController = nil;

@interface PSViewController(Private)
-(void)viewWillAppear:(BOOL)animated;
@end

@implementation CLEffectsController
@synthesize effects = _effects, selectedEffects=_selectedEffects;

- (instancetype)init
{
	if (self = [super init])
    {
        _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height) style:UITableViewStyleGrouped];
        _tableView.dataSource = self;
        _tableView.delegate = self;
        // _tableView.editing = false;
        // _tableView.allowsSelection = true;

        // _tableView.allowsMultipleSelection = false;
        // _tableView.allowsSelectionDuringEditing = true;
        // _tableView.allowsMultipleSelectionDuringEditing = true;
    
		if ([self respondsToSelector:@selector(setView:)])
			[self performSelectorOnMainThread:@selector(setView:) withObject:_tableView waitUntilDone:YES];

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0,0,10,10)];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
        self.titleLabel.text = @"Effects";
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.navigationItem.titleView = [UIView new];
        [self.navigationItem.titleView addSubview:self.titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.navigationItem.titleView.topAnchor],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.navigationItem.titleView.leadingAnchor],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.navigationItem.titleView.trailingAnchor],
            [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.navigationItem.titleView.bottomAnchor],
        ]];

        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOCALIZE(@"RESET_EFFECTS", @"Clear") style:UIBarButtonItemStylePlain target:self action:@selector(clear:)];

	}
    sharedController = self;
	return self;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"WARNING: combining certain 3D effects may cause lag";
    }
    return nil;
}

- (void)addEffectsFromDirectory:(NSString *)directory
{
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Ant Lines (Horizontal)" selectorName:@"horizontalAntLines" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Ant Lines (Vertical)" selectorName:@"verticalAntLines" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Backwards" selectorName:@"backwards" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Card (Horizontal)" selectorName:@"cardHorizontal" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Card (Vertical)" selectorName:@"cardVertical" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Checkerboard Scatter" selectorName:@"scatter" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Chomp" selectorName:@"chomp" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Cube Inside" selectorName:@"cubeInside" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Cube Outside" selectorName:@"cubeOutside" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Double Door" selectorName:@"doubleDoor" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Helix" selectorName:@"doubleHelix" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Hinge" selectorName:@"hinge" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Hyperspace" selectorName:@"hyperspace" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Icon Collection" selectorName:@"iconCollection" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Left Stairs" selectorName:@"leftStairs" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Right Stairs" selectorName:@"rightStairs" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Page Fade" selectorName:@"pageFade" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Page Flip" selectorName:@"pageFlip" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Page Twist" selectorName:@"pageTwist" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Psychospiral" selectorName:@"psychospiral" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Shrink" selectorName:@"shrink" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Spin" selectorName:@"spin" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Suck" selectorName:@"suck" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Vertical Scrolling" selectorName:@"verticalScrolling" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Vortex" selectorName:@"vortex" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Wave" selectorName:@"wave" developer:@"Ryan Nair"]];
    [self.effects addObject:[[CLEffect alloc] initWithName:@"Wheel" selectorName:@"wheel" developer:@"Ryan Nair"]];
    
    // if(effect)
        // [self.effects addObject:effect];

    [self.effects sortUsingComparator:^NSComparisonResult(CLEffect *effect1, CLEffect *effect2)
    {
        return [effect1.name compare:effect2.name];
    }];
}

-(CLEffect *)effectWithName:(NSString *)name
{
    if(!name) return nil;

    for(CLEffect *effect in self.effects)
    {
        if([effect.name isEqualToString:name])
        {
            return effect;
        }
    }
    return nil;
}

- (void)refreshList
{
    self.effects = [NSMutableArray array];
    CylinderSettingsListController *ctrl = (CylinderSettingsListController*)self.parentController;
    [self addEffectsFromDirectory:nil];

    NSArray *effects = [ctrl.settings objectForKey:PrefsEffectKey];
    self.selectedEffects = [NSMutableArray array];

    for(NSDictionary *dict in effects)
    {
        NSString *name = [dict objectForKey:PrefsEffectKey];
        CLEffect *effect = [self effectWithName:name];
        effect.selected = true;
        if(effect)
            [self.selectedEffects addObject:effect];
    }
}

- (void)clear:(id)sender
{
    for(CLEffect *effect in self.selectedEffects)
    {
        effect.selected = false;
    }

    self.selectedEffects = [NSMutableArray array];
    [_tableView reloadData];

    [self updateSettings];
}

- (void)viewWillAppear:(BOOL)animated
{
    if(!_initialized)
    {
        [self refreshList];
        _initialized = true;
    }
    [super viewWillAppear:animated];

}

- (void)dealloc
{
    sharedController = nil;
}

- (id)view
{
    return _tableView;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.effects.count;

}

-(id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CLAlignedTableViewCell *cell = (CLAlignedTableViewCell*)[tableView dequeueReusableCellWithIdentifier:@"EffectCell"];
    if (!cell)
    {
        cell = [CLAlignedTableViewCell.alloc initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"EffectCell"];
        cell.textLabel.adjustsFontSizeToFitWidth = true;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    CLEffect *effect = [self.effects objectAtIndex:indexPath.row];
    effect.cell = cell;

    cell.textLabel.text = effect.name;
    cell.detailTextLabel.text = effect.developer;

    cell.numberLabel.text = effect.selected ? [NSString stringWithFormat:@"%lu", ([self.selectedEffects indexOfObject:effect] + 1)] : @"";

    return cell;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!tableView.isEditing)
    {
        // deselect old one
        [tableView deselectRowAtIndexPath:indexPath animated:true];

        CLEffect *effect = [self.effects objectAtIndex:indexPath.row];
        effect.selected = !effect.selected;

        if(effect.selected)
        {
            [self.selectedEffects addObject:effect];
            CLEffect *e = [self.selectedEffects objectAtIndex: self.selectedEffects.count-1];
            CLAlignedTableViewCell *cell = (CLAlignedTableViewCell *)e.cell;
            cell.numberLabel.text = [NSString stringWithFormat:@"%lu",  self.selectedEffects.count];
        }
        else
        {
            effect.cell.numberLabel.text = @"";
            [self.selectedEffects removeObject:effect];
        }

        [self updateSettings];
    }
}

-(void)updateSettings
{
    // make the title changes
    CylinderSettingsListController *ctrl = (CylinderSettingsListController*)self.parentController;
    ctrl.selectedEffects = self.selectedEffects;
}

@end