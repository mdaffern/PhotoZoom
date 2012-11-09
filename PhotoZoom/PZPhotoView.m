//
//  PZPhotoView.m
//  PhotoZoom
//
//  Created by Brennan Stehling on 10/27/12.
//  Copyright (c) 2012 SmallSharptools LLC. All rights reserved.
//

#import "PZPhotoView.h"

#define kZoomStep 1.5

@interface PZPhotoView () <UIScrollViewDelegate>

@property (weak, nonatomic) UIImageView *imageView;

@end

@implementation PZPhotoView {
    CGPoint  _pointToCenterAfterResize;
    CGFloat  _scaleToRestoreAfterResize;
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setupView];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self setupView];
}

- (void)setupView {
    self.delegate = self;
    self.imageView = nil;
    
    self.showsVerticalScrollIndicator = NO;
    self.showsHorizontalScrollIndicator = NO;
    self.bouncesZoom = TRUE;
    self.decelerationRate = UIScrollViewDecelerationRateFast;
    
    self.contentInset = UIEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    // center the zoom view as it becomes smaller than the size of the screen
    CGSize boundsSize = self.bounds.size;
    CGRect frameToCenter = self.imageView.frame;

    // center horizontally
    if (frameToCenter.size.width < boundsSize.width)
        frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2;
    else
        frameToCenter.origin.x = 0;

    // center vertically
    if (frameToCenter.size.height < boundsSize.height)
        frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2;
    else
        frameToCenter.origin.y = 0;

    self.imageView.frame = frameToCenter;
    
    CGPoint contentOffset = self.contentOffset;
    
    // ensure horizontal offset is reasonable
    if (frameToCenter.origin.x != 0.0)
        contentOffset.x = 0.0;
    
    // ensure vertical offset is reasonable
    if (frameToCenter.origin.y != 0.0)
        contentOffset.y = 0.0;
    
    self.contentOffset = contentOffset;
    
    // ensure content insert is zeroed out using translucent navigation bars
    self.contentInset = UIEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
}

- (void)setFrame:(CGRect)frame {
    BOOL sizeChanging = !CGSizeEqualToSize(frame.size, self.frame.size);
    
    if (sizeChanging) {
        [self prepareToResize];
    }
    
    [super setFrame:frame];
    
    if (sizeChanging) {
        [self recoverFromResizing];
    }
}

#pragma mark - Public Implementation
#pragma mark -

- (void)displayImage:(UIImage *)image {
    // start by dropping any views and resetting the key properties
    for (UIView *view in self.subviews) {
        [view removeFromSuperview];
    }
    
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.userInteractionEnabled = TRUE;
    [self addSubview:imageView];
    self.imageView = imageView;
    
    // add gesture recognizers to the image view
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    UITapGestureRecognizer *twoFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTwoFingerTap:)];
    UITapGestureRecognizer *doubleTwoFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTwoFingerTap:)];
    
    [doubleTap setNumberOfTapsRequired:2];
    [twoFingerTap setNumberOfTouchesRequired:2];
    [doubleTwoFingerTap setNumberOfTapsRequired:2];
    [doubleTwoFingerTap setNumberOfTouchesRequired:2];
    
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [twoFingerTap requireGestureRecognizerToFail:doubleTwoFingerTap];
    
    [self.imageView addGestureRecognizer:singleTap];
    [self.imageView addGestureRecognizer:doubleTap];
    [self.imageView addGestureRecognizer:twoFingerTap];
    [self.imageView addGestureRecognizer:doubleTwoFingerTap];
    
    self.contentSize = self.imageView.frame.size;
    
    [self setMaxMinZoomScalesForCurrentBounds];
    [self setZoomScale:self.minimumZoomScale animated:FALSE];
    
    // prepare the layout for full screen when status bar, navigation bar and toolbar/tabbar are hidden
    CGRect applicationFrame = [UIScreen mainScreen].applicationFrame;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        CGRect frame = self.frame;
        frame.origin.y = -20.0; // move up under translucent status bar
        frame.size.height = applicationFrame.size.height + 20.0; // increase height
        self.frame = frame;
    });
}

#pragma mark - Gestures
#pragma mark -

- (void)handleSingleTap:(UIGestureRecognizer *)gestureRecognizer {
    if (self.photoViewDelegate != nil) {
        [self.photoViewDelegate photoViewDidSingleTap:self];
    }
}

- (void)handleDoubleTap:(UIGestureRecognizer *)gestureRecognizer {
    if (self.zoomScale == self.maximumZoomScale) {
        // jump back to minimum scale
        [self updateZoomScaleWithGesture:gestureRecognizer newScale:self.minimumZoomScale];
    }
    else {
        // double tap zooms in
        CGFloat newScale = MIN([self zoomScale] * kZoomStep, self.maximumZoomScale);
        
        if (self.zoomScale != newScale)
            [self updateZoomScaleWithGesture:gestureRecognizer newScale:newScale];
    }
    
    if (self.photoViewDelegate != nil) {
        [self.photoViewDelegate photoViewDidDoubleTap:self];
    }
}

- (void)handleTwoFingerTap:(UIGestureRecognizer *)gestureRecognizer {
    // two-finger tap zooms out
    CGFloat newScale = MAX([self zoomScale] / kZoomStep, self.minimumZoomScale);
    
    if (self.zoomScale != newScale)
        [self updateZoomScaleWithGesture:gestureRecognizer newScale:newScale];
    
    if (self.photoViewDelegate != nil) {
        [self.photoViewDelegate photoViewDidTwoFingerTap:self];
    }
}

- (void)handleDoubleTwoFingerTap:(UIGestureRecognizer *)gestureRecognizer {
    if (self.photoViewDelegate != nil) {
        [self.photoViewDelegate photoViewDidDoubleTwoFingerTap:self];
    }
}

#pragma mark - Support Methods
#pragma mark -

- (void)updateZoomScale:(CGFloat)newScale {
    CGPoint center = CGPointMake(self.imageView.bounds.size.width/ 2.0, self.imageView.bounds.size.height / 2.0);
    [self updateZoomScale:newScale withCenter:center];
}

- (void)updateZoomScaleWithGesture:(UIGestureRecognizer *)gestureRecognizer newScale:(CGFloat)newScale {
    CGPoint center = [gestureRecognizer locationInView:gestureRecognizer.view];
    [self updateZoomScale:newScale withCenter:center];
}

- (void)updateZoomScale:(CGFloat)newScale withCenter:(CGPoint)center {
    assert(newScale >= self.minimumZoomScale);
    assert(newScale <= self.maximumZoomScale);

    CGRect zoomRect = [self zoomRectForScale:newScale withCenter:center];
    [self zoomToRect:zoomRect animated:YES];
}

- (CGRect)zoomRectForScale:(float)scale withCenter:(CGPoint)center {
    assert(scale >= self.minimumZoomScale);
    assert(scale <= self.maximumZoomScale);
    
    CGRect zoomRect;
    
    // the zoom rect is in the content view's coordinates.
    zoomRect.size.width = self.frame.size.width / scale;
    zoomRect.size.height = self.frame.size.height / scale;
    
    // choose an origin so as to get the right center.
    zoomRect.origin.x = center.x - (zoomRect.size.width / 2.0);
    zoomRect.origin.y = center.y - (zoomRect.size.height / 2.0);
    
    return zoomRect;
}

- (void)setMaxMinZoomScalesForCurrentBounds {
    // calculate minimum scale to perfectly fit image width, and begin at that scale
    CGSize boundsSize = self.bounds.size;
    
    // on high resolution screens we have double the pixel density, so we will be seeing every pixel if we limit the
    // maximum zoom scale to 0.5.
    CGFloat maxScale = 1.0 / [[UIScreen mainScreen] scale];
    
    CGFloat minScale  = maxScale; // default
    
    // calculate min/max zoomscale
    CGFloat xScale = boundsSize.width  / self.imageView.bounds.size.width;    // the scale needed to perfectly fit the image width-wise
    CGFloat yScale = boundsSize.height / self.imageView.bounds.size.height;   // the scale needed to perfectly fit the image height-wise

    // fill width if the image and phone are both portrait or both landscape; otherwise take smaller scale
    BOOL imagePortrait = self.imageView.bounds.size.height > self.imageView.bounds.size.width;
    BOOL phonePortrait = boundsSize.height > boundsSize.width;
    minScale = imagePortrait == phonePortrait ? xScale : MIN(xScale, yScale);
    
    // don't let minScale exceed maxScale. (If the image is smaller than the screen, we don't want to force it to be zoomed.)
    if (minScale > maxScale) {
        minScale = maxScale / 2.0;
    }
    
    self.maximumZoomScale = maxScale;
    self.minimumZoomScale = minScale;
}

- (void)prepareToResize {
    CGPoint boundsCenter = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    _pointToCenterAfterResize = [self convertPoint:boundsCenter toView:self.imageView];
    
    _scaleToRestoreAfterResize = self.zoomScale;
    
    // If we're at the minimum zoom scale, preserve that by returning 0, which will be converted to the minimum
    // allowable scale when the scale is restored.
    if (_scaleToRestoreAfterResize <= self.minimumZoomScale + FLT_EPSILON)
        _scaleToRestoreAfterResize = 0;
}

- (void)recoverFromResizing {
    [self setMaxMinZoomScalesForCurrentBounds];
    
    // Step 1: restore zoom scale, first making sure it is within the allowable range.
    CGFloat maxZoomScale = MAX(self.minimumZoomScale, _scaleToRestoreAfterResize);
    self.zoomScale = MIN(self.maximumZoomScale, maxZoomScale);
    
    // Step 2: restore center point, first making sure it is within the allowable range.
    
    // 2a: convert our desired center point back to our own coordinate space
    CGPoint boundsCenter = [self convertPoint:_pointToCenterAfterResize fromView:self.imageView];
    
    // 2b: calculate the content offset that would yield that center point
    CGPoint offset = CGPointMake(boundsCenter.x - self.bounds.size.width / 2.0,
                                 boundsCenter.y - self.bounds.size.height / 2.0);
    
    // 2c: restore offset, adjusted to be within the allowable range
    CGPoint maxOffset = [self maximumContentOffset];
    CGPoint minOffset = [self minimumContentOffset];
    
    CGFloat realMaxOffset = MIN(maxOffset.x, offset.x);
    offset.x = MAX(minOffset.x, realMaxOffset);
    
    realMaxOffset = MIN(maxOffset.y, offset.y);
    offset.y = MAX(minOffset.y, realMaxOffset);
    
    self.contentOffset = offset;
}

- (CGPoint)maximumContentOffset {
    CGSize contentSize = self.contentSize;
    CGSize boundsSize = self.bounds.size;
    return CGPointMake(contentSize.width - boundsSize.width, contentSize.height - boundsSize.height);
}

- (CGPoint)minimumContentOffset {
    return CGPointZero;
}

#pragma mark - UIScrollViewDelegate Methods
#pragma mark -

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

@end
