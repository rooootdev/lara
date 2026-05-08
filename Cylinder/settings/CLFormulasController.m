#import "../Defines.h"
#import "CLFormulasController.h"

#define ADD_SECTION 0
#define FORMULA_SECTION 1


@interface PSViewController(Private)
-(void)viewWillAppear:(BOOL)animated;
-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
@end


@implementation CLFormulasController
@synthesize formulas=_formulas,selectedFormula=_selectedFormula, editButton=_editButton;

- (instancetype)init
{
	if (self = [super init])
    {
		_tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height) style:UITableViewStyleGrouped];
        _tableView.dataSource = self;
        _tableView.delegate = self;
        //_tableView.allowsSelection = true;
        //_tableView.allowsSelectionDuringEditing = true;

        /*
			[_tableView setAllowsMultipleSelection:NO];
			[_tableView setAllowsSelectionDuringEditing:YES];
			[_tableView setAllowsMultipleSelectionDuringEditing:YES];
        */

		if ([self respondsToSelector:@selector(setView:)])
			[self performSelectorOnMainThread:@selector(setView:) withObject:_tableView waitUntilDone:YES];	

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0,0,10,10)];
        titleLabel.font = [UIFont boldSystemFontOfSize:17];
        titleLabel.text = @"Formulas";
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.navigationItem.titleView = [UIView new];
        [self.navigationItem.titleView addSubview:titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:self.navigationItem.titleView.topAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.navigationItem.titleView.leadingAnchor],
            [titleLabel.trailingAnchor constraintEqualToAnchor:self.navigationItem.titleView.trailingAnchor],
            [titleLabel.bottomAnchor constraintEqualToAnchor:self.navigationItem.titleView.bottomAnchor],
        ]];

        self.editButton = [[UIBarButtonItem alloc] initWithTitle:@"Edit" style:UIBarButtonItemStylePlain target:self action:@selector(editButtonPressed:)];

        self.navigationItem.rightBarButtonItem = self.editButton;
	}
	return self;
}

- (void)refreshList
{
    CylinderSettingsListController *ctrl = (CylinderSettingsListController*)self.parentController;

    NSDictionary *formulas = [ctrl.settings objectForKey:PrefsFormulaKey];
    if(!formulas || ![formulas isKindOfClass:NSDictionary.class])
    {
        self.formulas = [NSMutableDictionary dictionary];
    }
    else
    {
        self.formulas = formulas.mutableCopy;
        /*
        self.formulas = [NSMutableDictionary dictionaryWithCapacity:formulas.count];
        for(NSString *key in formulas)
        {
            NSArray *effectDicts = [formulas objectForKey:key];
            NSMutableArray *effects = [NSMutableArray arrayWithCapacity:effectDicts.count];
            for(NSDictionary *effectDict in effectDicts)
            {
                NSString *dir = [effectDict objectForKey:PrefsEffectDirKey];
                NSString *name = [effectDict objectForKey:PrefsEffectKey];

                if(dir && name)
                {
                    NSString *path = [[kEffectsDirectory stringByAppendingPathComponent:dir] stringByAppendingPathComponent:name];
                    CLEffect *effect = [CLEffect effectWithPath:path];
                    if(effect)
                        [effects addObject:effectDict];
                }
            }
            [self.formulas setObject:effects forKey:key];
        }
        */
    }

    self.selectedFormula = [ctrl.settings objectForKey:PrefsSelectedFormulaKey];
}

-(void)showAlertWithText:(NSString *)text
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle: nil message: text preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *create = [UIAlertAction actionWithTitle: LOCALIZE(@"CREATE_FORMULA", @"Create Formula") style: UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *name = alert.textFields.firstObject.text;
                    
        if(name.length == 0)
        {
            [self showAlertWithText:@"You didn't type anything."];
        }
        else if([self.formulas objectForKey:name])
        {
            UIAlertController *sameNameAlert = [UIAlertController alertControllerWithTitle:nil message:LOCALIZE(@"FORMULA_ALREADY_EXISTS", @"A formula with that name already exists.") preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *overWrite = [UIAlertAction actionWithTitle: LOCALIZE(@"OVERWRITE_IT", @"Overwrite it") style: UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
                NSString *_theFormulaName = alert.textFields.firstObject.text;
                if(name.length == 0)
                {
                    [self showAlertWithText:@"You didn't type anything."];
                }
                else {
                    [self createFormulaWithName:_theFormulaName];
                    _theFormulaName = nil;
                }
            }];

            UIAlertAction *cancelOverwrite = [UIAlertAction actionWithTitle:LOCALIZE(@"CANCEL", @"Cancel") style:UIAlertActionStyleCancel handler: nil];

            [sameNameAlert addAction:cancelOverwrite];
            [sameNameAlert addAction:overWrite];
            [self presentViewController:sameNameAlert animated:YES completion:nil];
        }
        else
        {
            [self createFormulaWithName:name];
        }
    }];

    UIAlertAction *cancel = [UIAlertAction actionWithTitle:LOCALIZE(@"CANCEL", @"Cancel") style:UIAlertActionStyleCancel handler: nil];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = LOCALIZE(@"FORMULA_NAME", @"Formula name");
    }];

    [alert addAction:create];
    [alert addAction:cancel];

    [self presentViewController:alert animated:YES completion:nil];
}

-(void)createFormulaWithName:(NSString *)name
{
    CylinderSettingsListController *ctrl = (CylinderSettingsListController*)self.parentController;
    NSArray *effects = [ctrl.settings objectForKey:PrefsEffectKey];

    if(!effects)
    {
        [self showAlertWithText:@"IT DIDN'T WORK!"];
        return;
    }

    [self.formulas setObject:effects forKey:name];
    self.selectedFormula = name;
    [self updateSettings];
    [_tableView reloadData];
}

- (void)editButtonPressed:(id)sender
{
    if(_tableView.editing)
    {
        [_tableView setEditing:false animated:true];
        self.editButton.title = @"Edit";
    }
    else
    {
        [_tableView setEditing:true animated:true];
        self.editButton.title = @"Done";
    }

}

- (void)viewWillAppear:(BOOL)animated
{
    if(!_initialized)
    {
        [self refreshList];
        _initialized = true;
    }
    [super viewWillAppear:animated];
    //_tableView.editing = true;

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

-(NSString *)keyForIndex:(int)index
{
    int i = 0;
    for(NSString *key in self.formulas)
    {
        if(i == index) return key;
        i++;
    }
    return nil;
}

-(NSUInteger)indexForKey:(NSString *)key
{
    NSUInteger i = 0;
    for(NSString *k in self.formulas)
    {
        if([k isEqualToString:key]) return i;
        i++;
    }
    return NSNotFound;
}


- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if(section == ADD_SECTION)
        return 1;
        
    return self.formulas.count;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(indexPath.section == ADD_SECTION) return false;
    // Return NO if you do not want the specified item to be editable.
    return true;
}


-(id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"EffectCell"];
    if (!cell)
    {
        cell = [UITableViewCell.alloc initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"EffectCell"];
        cell.textLabel.adjustsFontSizeToFitWidth = true;
        //cell.editing = true;
        //cell.shouldIndentWhileEditing = false;
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selected = false;

    if(indexPath.section == ADD_SECTION)
    {
        cell.textLabel.text = LOCALIZE(@"CREATE_NEW_FORMULA", @"Create new formula");
        cell.imageView.image = [UIImage systemImageNamed:@"plus.app"];
    }
    else if(indexPath.section == FORMULA_SECTION)
    {
        NSString *name = [self keyForIndex:indexPath.row];
        BOOL selected = [name isEqualToString:self.selectedFormula];
        cell.textLabel.text = name;
        if(selected)
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        cell.imageView.image = nil;
    }

    return cell;
}

-(void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete)
    {
        NSString *key = [self keyForIndex:indexPath.row];
        [self.formulas removeObjectForKey:key];
        [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self updateSettings];
    }
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(indexPath.section == ADD_SECTION)
    {
        CylinderSettingsListController *ctrl = (CylinderSettingsListController*)self.parentController;

        NSDictionary *effects = [ctrl.settings objectForKey:PrefsEffectKey];

        if(effects.count == 0)
        {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOCALIZE(@"NO_EFFECTS_ENABLED_TITLE", @"You have no effects enabled!") message:LOCALIZE(@"NO_EFFECTS_ENABLED_DESC", @"Go back to the effects list, enable some effects, then come back here and create a new formula.") preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* cancelButton = [UIAlertAction actionWithTitle:LOCALIZE(@"NO_EFFECTS_ENABLED_OK", @"Aight cool") style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}];
            [alert addAction:cancelButton];
            [self presentViewController:alert animated:YES completion:nil];
        }
        else
        {
            [self showAlertWithText:LOCALIZE(@"CREATE_FORMULA_INFO", @"The new formula will have whatever effects you have enabled right now.")];
        }
    }
    else if(indexPath.section == FORMULA_SECTION)
    {
        if(self.selectedFormula)
        {
            int index = [self indexForKey:self.selectedFormula];
            UITableViewCell *cell = [_tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:FORMULA_SECTION]];
            cell.accessoryType = UITableViewCellAccessoryNone;
        }

        self.selectedFormula = [self keyForIndex:indexPath.row];
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        cell.accessoryType = UITableViewCellAccessoryCheckmark;

        [self updateSettings];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:true];
}

-(void)updateSettings
{
    // make the title changes
    CylinderSettingsListController *ctrl = (CylinderSettingsListController*)self.parentController;
    ctrl.formulas = self.formulas;
    ctrl.selectedFormula = self.selectedFormula;
    [ctrl writeSettings];
}

@end
