//
//  ThreadViewController.m
//  m2ch
//
//  Created by Александр Тюпин on 08/05/14.
//  Copyright (c) 2014 Alexander Tewpin. All rights reserved.
//

#import "ThreadViewController.h"
#import "BoardViewController.h"
#import "GetRequestViewController.h"
#import "UrlNinja.h"
#import "JTSImageViewController.h"
#import "JTSImageInfo.h"

@interface ThreadViewController ()

@end

@implementation ThreadViewController


- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerClass:[PostTableViewCell class] forCellReuseIdentifier:@"reuseIndenifier"];
    self.tableView.estimatedRowHeight = UITableViewAutomaticDimension;
    self.navigationItem.title = [NSString stringWithFormat:@"Тред в /%@/", self.boardId];
    
    UIButton *moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    moreButton.frame = CGRectMake(0, 0, self.tableView.frame.size.width, 44);

    [moreButton setTitle:@"Еще посты" forState:UIControlStateNormal];
    [moreButton addTarget:self action:@selector(loadMorePostsUp) forControlEvents:UIControlEventTouchUpInside];
    
    self.refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.refreshButton.frame = CGRectMake(0, 0, 320, 44);
    [self.refreshButton setTitle:@"Обновить тред" forState:UIControlStateNormal];
    [self.refreshButton setTitle:@"Загрузка..." forState:UIControlStateDisabled];
    [self.refreshButton addTarget:self action:@selector(loadData) forControlEvents:UIControlEventTouchUpInside];
    
    self.tableView.tableHeaderView = moreButton;
    self.tableView.tableFooterView = self.refreshButton;
    
    self.tableView.tableHeaderView.hidden = YES;
    
    [self loadData];
}

- (void)loadData {
    [self updateStarted];
    NSString *threadStringUrl = [[[[[@"http://2ch.hk/" stringByAppendingString:@"makaba/mobile.fcgi?task=get_thread&board="]stringByAppendingString:self.boardId]stringByAppendingString:@"&thread="]stringByAppendingString:self.threadId]stringByAppendingString:@"&post=1"];
    NSURL *threadUrl = [NSURL URLWithString:threadStringUrl];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    NSURLSessionDownloadTask *task = [session downloadTaskWithURL:threadUrl];
    [task resume];
}

#pragma mark - URL Session Handling

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {

    NSData *data = [NSData dataWithContentsOfURL:location];
    
    //асинхронное задание по созданию массива
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        NSError *dataError = nil;
        NSArray *dataArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:&dataError];
        
        self.thread = [[Thread alloc]init];
        self.thread.posts = [NSMutableArray array];
        self.thread.linksReference = [NSMutableArray array];
        
        for (NSDictionary *dic in dataArray) {
            Post *post = [Post postWithDictionary:dic andBoardId:self.boardId];
            [self.thread.posts addObject:post];
            [self.thread.linksReference addObject:[NSString stringWithFormat:@"%ld", (long)post.num]];
        }
        
        //в текущий вид грузим только последние 50 постов
        self.currentThread = [Thread currentThreadWithThread:self.thread];
        
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [self performSelectorOnMainThread:@selector(updateEnded) withObject:nil waitUntilDone:YES];
            
            //этот код скроллинга для ячейки фачит отображение таблицы, если там мало постов
            //должно вызываться только в первый раз
            if (self.postId) {
                NSIndexPath *index = [NSIndexPath indexPathForRow:[self.thread.linksReference indexOfObject:self.postId] inSection:0];
                [self scrollToRowAnimated:index isAnimated:NO];
            } else {
                if (self.tableView.contentSize.height > self.tableView.frame.size.height) {
                    CGPoint offset = CGPointMake(0, self.tableView.contentSize.height - self.tableView.frame.size.height);
                    [self.tableView setContentOffset:offset animated:NO];
                }
            }
        });
    });   
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes {
    
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
}

- (void)updateStarted {
    self.refreshButton.enabled = NO;
}

- (void)updateEnded {
    [self.tableView reloadData];
    self.refreshButton.enabled = YES;
    self.tableView.tableHeaderView.hidden = NO;
    
    if (self.thread.posts.count == self.currentThread.posts.count) {
        self.tableView.tableHeaderView = nil;
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.currentThread.posts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    PostTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"reuseIndenifier"];
    
    [cell updateFonts];
    
    Post *post = self.currentThread.posts[indexPath.row];
    
    [cell setPost:post];
    
    [cell setNeedsUpdateConstraints];
    [cell updateConstraintsIfNeeded];
    
    cell.comment.delegate = self;
    
    UITapGestureRecognizer *tgr = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(imageTapped:)];
    UILongPressGestureRecognizer *lpgr = [[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(postLongPress:)];
    
    lpgr.minimumPressDuration = 0.5;
    [cell.comment setTag:cell.num];
    
    tgr.delegate = self;
    lpgr.delegate = self;
    
    [cell addGestureRecognizer:lpgr];
    [cell.postImage addGestureRecognizer:tgr];
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (self == self.navigationController.topViewController) {
        
        Post *post = self.currentThread.posts[indexPath.row];
        
        if (post.postHeight) {
            return post.postHeight;
        } else {
        
            PostTableViewCell *cell = [[PostTableViewCell alloc]init];
            
            [cell setPost:post];
            
            [cell setNeedsUpdateConstraints];
            [cell updateConstraintsIfNeeded];
            
            cell.bounds = CGRectMake(0.0f, 0.0f, CGRectGetWidth(tableView.bounds), CGRectGetHeight(cell.bounds));
            
            [cell setNeedsLayout];
            [cell layoutIfNeeded];
            
            CGFloat height = [cell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
            
            height += 1;
            post.postHeight = height;
            [self.currentThread.posts removeObjectAtIndex:indexPath.row];
            [self.currentThread.posts insertObject:post atIndex:indexPath.row];
           
            return height;
        }
    }
    
    return 0;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [UIView animateWithDuration:0.1 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionCurveEaseInOut animations:^
     {
         [[self.tableView cellForRowAtIndexPath:indexPath] setSelected:NO animated:YES];
     } completion: NULL];
}

#pragma mark - Posting and draft handling

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"newPost"]) {
        UINavigationController *navigationController = segue.destinationViewController;
        GetRequestViewController *destinationController = (GetRequestViewController *)navigationController.topViewController;
        [destinationController setBoardId:self.boardId];
        [destinationController setThreadId:self.threadId];
        [destinationController setDraft:self.thread.postDraft];
        destinationController.postView.text = self.thread.postDraft;
        destinationController.delegate = self;
    }
}

- (void)postCanceled:(NSString *)draft{
    self.thread.postDraft = draft;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)postPosted {
    [self loadData];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - TTTAttributedLabelDelegate

- (void)attributedLabel:(__unused TTTAttributedLabel *)label didSelectLinkWithURL:(NSURL *)url {

    UrlNinja *urlNinja = [UrlNinja unWithUrl:url];
    
    switch (urlNinja.type) {
        case boardLink: {
            //открыть борду
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:nil];
            BoardViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"BoardTag"];
            controller.boardId = urlNinja.boardId;
            [self.navigationController pushViewController:controller animated:YES];
            break;
        }
        case boardThreadLink: {
            //открыть тред
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:nil];
            ThreadViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"ThreadTag"];
            controller.boardId = urlNinja.boardId;
            controller.threadId = urlNinja.threadId;
            
            //без этого фачится размер заголовка
            controller.navigationItem.title = [NSString stringWithFormat:@"Тред в /%@/", urlNinja.boardId];

            [self.navigationController pushViewController:controller animated:YES];
            break;
        }
        case boardThreadPostLink:
            //проскроллить страницу
            if ([urlNinja.boardId isEqualToString:self.boardId] && [urlNinja.threadId isEqualToString:self.threadId]) {
                NSIndexPath *index = [NSIndexPath indexPathForRow:[self.thread.linksReference indexOfObject:urlNinja.postId] inSection:0];
                [self scrollToRowAnimated:index isAnimated:YES];
                }
                //открыть тред и проскроллить страницу
                else {
                    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:nil];
                    ThreadViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"ThreadTag"];
                    controller.boardId = urlNinja.boardId;
                    controller.threadId = urlNinja.threadId;
                    controller.postId = urlNinja.postId;
                    [self.navigationController pushViewController:controller animated:YES];
                    break;
                }
            break;
        default: {
            //внешня ссылка - предложение открыть в сафари
            UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:[url absoluteString] delegate:self cancelButtonTitle:NSLocalizedString(@"Отмена", nil) destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Открыть ссылку в Safari", nil), nil];
            actionSheet.tag = 2;
            [actionSheet showInView:self.view];
            break;
        }
    }
}

- (void)scrollToRowAnimated: (NSIndexPath *)index isAnimated:(BOOL)animated {
    
    //вычисления для анимации
    CGRect cellRect = [self.tableView rectForRowAtIndexPath:index];
    CGRect superRect = [self.tableView convertRect:cellRect toView:[self.tableView superview]];
    
    [self.tableView scrollToRowAtIndexPath:index atScrollPosition:UITableViewScrollPositionTop animated:animated];
    
    //анимация, если пост уже на топе пользователя, 64 это магическое число обозначающее высоту скроллбара, потом надо переделать на нормальное
    if (superRect.origin.y == 64.0) {
        [UIView animateWithDuration:0.1 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionCurveEaseInOut animations:^
         {
             [[self.tableView cellForRowAtIndexPath:index] setHighlighted:YES animated:YES];
         } completion:^(BOOL finished)
         {
             [UIView animateWithDuration:0.1 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionCurveEaseInOut animations:^
              {
                  [[self.tableView cellForRowAtIndexPath:index] setHighlighted:NO animated:YES];
              } completion: NULL];
         }];
    }
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if(actionSheet.tag == 1) // лонгпресс по посту
    {
        if (buttonIndex == actionSheet.cancelButtonIndex) {
            return;
        } else if (buttonIndex == 0) { // ответить
            if (![self.thread.postDraft isEqualToString:@""] && self.thread.postDraft) {
                self.thread.postDraft = [NSString stringWithFormat:@"%@%@\n", self.thread.postDraft, self.reply];
            } else {
                self.thread.postDraft = [NSString stringWithFormat:@"%@\n", self.reply];
            }
        } else if (buttonIndex == 1) { //ответ с цитатой
            if (![self.thread.postDraft isEqualToString:@""] && self.thread.postDraft) {
                self.thread.postDraft = [NSString stringWithFormat:@"%@\n%@\n%@\n", self.thread.postDraft, self.reply, self.quote];
            } else {
                self.thread.postDraft = [NSString stringWithFormat:@"%@\n%@\n", self.reply, self.quote];
            }
        }
        
        [self performSegueWithIdentifier:@"newPost" sender:self];
        
    } else if (actionSheet.tag == 2) { //клик по ссылке
        if (buttonIndex == actionSheet.cancelButtonIndex) {
            return;
        }
        //кстати, на конфе видел, что это хуевое решение, потому что юиаппликейнеш не должен за это отвечать и это как-то решается через делегирование
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:actionSheet.title]];
    }
}

- (void)imageTapped:(UITapGestureRecognizer *)sender {

    TapImageView *image = (TapImageView *)sender.view;
    // Create image info
    JTSImageInfo *imageInfo = [[JTSImageInfo alloc] init];
    
    NSLog(@"%@", image.bigImageUrl);
    imageInfo.imageURL = image.bigImageUrl;
    imageInfo.referenceRect = image.frame;
    imageInfo.referenceView = image.superview;
    
    // Setup view controller
    JTSImageViewController *imageViewer = [[JTSImageViewController alloc]
                                           initWithImageInfo:imageInfo
                                           mode:JTSImageViewControllerMode_Image
                                           backgroundStyle:JTSImageViewControllerBackgroundStyle_ScaledDimmed];
    
    // Present the view controller.
    [imageViewer showFromViewController:self transition:JTSImageViewControllerTransition_FromOffscreen];
}

- (void)postLongPress:(UIGestureRecognizer *)sender {
    
    if (sender.state == UIGestureRecognizerStateBegan){
        PostTableViewCell *cell = (PostTableViewCell *)sender.view;
        TTTAttributedLabel *post = cell.comment;
//        TTTAttributedLabel *post = (TTTAttributedLabel *)sender.view;
        self.reply = [@">>" stringByAppendingString:[NSString stringWithFormat:@"%ld", (long)cell.num]];
        self.quote = [self makeQuote:post.text];
    
        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:
          NSLocalizedString(@"Отмена", nil) destructiveButtonTitle:nil otherButtonTitles:
          NSLocalizedString(@"Ответить", nil),
          NSLocalizedString(@"Ответить с цитатой", nil), nil];
        actionSheet.tag = 1;
        [actionSheet showInView:self.view];
    }
}

- (NSString *)makeQuote:(NSString *)sourceString {
    NSMutableString *mString = [sourceString mutableCopy];
    NSMutableArray *resultArray = [NSMutableArray array];
    NSRegularExpression *quoteReg = [NSRegularExpression regularExpressionWithPattern:@"^.+$" options:NSRegularExpressionAnchorsMatchLines error:nil];
    [quoteReg enumerateMatchesInString:sourceString options:0 range:NSMakeRange(0, sourceString.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        [resultArray addObject:result];
    }];
    NSInteger shift = 0;
    for (NSTextCheckingResult *result in resultArray) {
        [mString insertString:@">" atIndex:result.range.location + shift];
        shift ++;
    }
    return mString;
}

#pragma mark - Loading and refreshing

- (void)loadMorePostsUp {

    [self.currentThread insertMorePostsFrom:self.thread];

    CGPoint newContentOffset = self.tableView.contentOffset;
    [self.tableView reloadData];
    
    for (NSIndexPath *indexPath in self.currentThread.updatedIndexes)
        newContentOffset.y += [self.tableView.delegate tableView:self.tableView heightForRowAtIndexPath:indexPath];
    
    if (self.thread.posts.count == self.currentThread.posts.count) {
        self.tableView.tableHeaderView = nil;
        newContentOffset.y -= 44;
    }
    
    [self.tableView setContentOffset:newContentOffset];
}
@end
