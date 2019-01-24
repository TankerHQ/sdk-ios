#import "TKRViewController.h"
#import "TKRTanker.h"

@interface TKRViewController ()
@property(weak, nonatomic) IBOutlet UILabel* versionField;
@end

@implementation TKRViewController

- (IBAction)goToValidation:(UIButton*)sender
{
}

- (void)viewWillAppear:(BOOL)animated
{
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  NSString* text = @"Version: ";
  text = [text stringByAppendingString:[TKRTanker versionString]];
  self->_versionField.text = text;
}

- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
}

@end
