//
// Copyright © 2019 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "UTMQemuSystem.h"
#import "UTMConfiguration.h"

@implementation UTMQemuSystem

- (id)initWithConfiguration:(UTMConfiguration *)configuration imgPath:(nonnull NSURL *)imgPath {
    self = [self init];
    if (self) {
        self.configuration = configuration;
        self.imgPath = imgPath;
    }
    return self;
}

- (void)architectureSpecificConfiguration {
    if ([self.configuration.systemArchitecture isEqualToString:@"x86_64"] ||
        [self.configuration.systemArchitecture isEqualToString:@"i386"]) {
        [self pushArgv:@"-vga"];
        [self pushArgv:@"qxl"];
    }
}

- (void)targetSpecificConfiguration {
    if ([self.configuration.systemTarget hasPrefix:@"virt"]) {
        if ([self.configuration.systemArchitecture isEqualToString:@"aarch64"]) {
            [self pushArgv:@"-cpu"];
            [self pushArgv:@"cortex-a72"];
        }
        // this is required for virt devices
        [self pushArgv:@"-device"];
        [self pushArgv:@"virtio-gpu-pci"];
        [self pushArgv:@"-device"];
        [self pushArgv:@"usb-ehci"];
        [self pushArgv:@"-device"];
        [self pushArgv:@"usb-mouse"];
        [self pushArgv:@"-device"];
        [self pushArgv:@"usb-kbd"];
        for (NSUInteger i = 0; i < self.configuration.countDrives; i++) {
            UTMDiskImageType type = [self.configuration driveImageTypeForIndex:i];
            if (type == UTMDiskImageTypeDisk || type == UTMDiskImageTypeCD) {
                [self pushArgv:@"-device"];
                [self pushArgv:[NSString stringWithFormat:@"virtio-blk,drive=drive%lu", i]];
            }
        }
    }
}

- (void)argsForDrives {
    for (NSUInteger i = 0; i < self.configuration.countDrives; i++) {
        NSString *path = [self.configuration driveImagePathForIndex:i];
        UTMDiskImageType type = [self.configuration driveImageTypeForIndex:i];
        NSURL *fullPathURL;
        
        if ([path characterAtIndex:0] == '/') {
            fullPathURL = [NSURL fileURLWithPath:path isDirectory:NO];
        } else {
            fullPathURL = [[self.imgPath URLByAppendingPathComponent:[UTMConfiguration diskImagesDirectory]] URLByAppendingPathComponent:[self.configuration driveImagePathForIndex:i]];
        }
        
        switch (type) {
            case UTMDiskImageTypeDisk:
            case UTMDiskImageTypeCD: {
                [self pushArgv:@"-drive"];
                [self pushArgv:[NSString stringWithFormat:@"file=%@,if=%@,media=%@,id=drive%lu", fullPathURL.path, [self.configuration driveInterfaceTypeForIndex:i], type == UTMDiskImageTypeCD ? @"cdrom" : @"disk", i]];
                break;
            }
            case UTMDiskImageTypeBIOS: {
                [self pushArgv:@"-bios"];
                [self pushArgv:fullPathURL.path];
                break;
            }
            case UTMDiskImageTypeKernel: {
                [self pushArgv:@"-kernel"];
                [self pushArgv:fullPathURL.path];
                break;
            }
            case UTMDiskImageTypeInitrd: {
                [self pushArgv:@"-initrd"];
                [self pushArgv:fullPathURL.path];
                break;
            }
            case UTMDiskImageTypeDTB: {
                [self pushArgv:@"-dtb"];
                [self pushArgv:fullPathURL.path];
                break;
            }
            default: {
                NSLog(@"WARNING: unknown image type %lu, ignoring image %@", type, fullPathURL);
                break;
            }
        }
    }
}

- (void)argsFromConfiguration {
    [self clearArgv];
    [self pushArgv:@"qemu"];
    [self pushArgv:@"-L"];
    [self pushArgv:[[NSBundle mainBundle] URLForResource:@"qemu" withExtension:nil].path];
    [self pushArgv:@"-qmp"];
    [self pushArgv:@"tcp:localhost:4444,server,nowait"];
    [self pushArgv:@"-smp"];
    [self pushArgv:[NSString stringWithFormat:@"cpus=%@,sockets=1", self.configuration.systemCPUCount]];
    [self pushArgv:@"-machine"];
    [self pushArgv:self.configuration.systemTarget];
    if (self.configuration.systemForceMulticore) {
        [self pushArgv:@"-accel"];
        [self pushArgv:@"tcg,thread=multi"];
    }
    if ([self.configuration.systemJitCacheSize integerValue] > 0) {
        [self pushArgv:@"-tb-size"];
        [self pushArgv:[self.configuration.systemJitCacheSize stringValue]];
    }
    [self architectureSpecificConfiguration];
    [self targetSpecificConfiguration];
    if (![self.configuration.systemBootDevice isEqualToString:@"hdd"]) {
        [self pushArgv:@"-boot"];
        if ([self.configuration.systemBootDevice isEqualToString:@"floppy"]) {
            [self pushArgv:@"order=ab"];
        } else {
            [self pushArgv:@"order=d"];
        }
    }
    [self pushArgv:@"-m"];
    [self pushArgv:[self.configuration.systemMemory stringValue]];
    if (self.configuration.soundEnabled) {
        [self pushArgv:@"-soundhw"];
        [self pushArgv:self.configuration.soundCard];
    }
    [self pushArgv:@"-name"];
    [self pushArgv:self.configuration.name];
    [self argsForDrives];
    if (self.configuration.displayConsoleOnly) {
        [self pushArgv:@"-display"];
        [self pushArgv:@"curses"];
    } else {
        [self pushArgv:@"-spice"];
        [self pushArgv:@"port=5930,addr=127.0.0.1,disable-ticketing,image-compression=off,playback-compression=off,streaming-video=off"];

    }
    if (self.configuration.networkEnabled) {
        [self pushArgv:@"-device"];
        [self pushArgv:@"rtl8139,netdev=net0"];
        [self pushArgv:@"-netdev"];
        NSMutableString *netstr = [NSMutableString stringWithString:@"user,id=net0"];
        if (self.configuration.networkIPSubnet) {
            [netstr appendFormat:@",net=%@", self.configuration.networkIPSubnet];
        }
        if (self.configuration.networkDHCPStart) {
            [netstr appendFormat:@",dhcpstart=%@", self.configuration.networkDHCPStart];
        }
        if (self.configuration.networkLocalhostOnly) {
            [netstr appendString:@"restrict=on"];
        }
        [self pushArgv:netstr];
    } else {
        [self pushArgv:@"-nic"];
        [self pushArgv:@"none"];
    }
    // usb input if not legacy
    if (!self.configuration.inputLegacy) {
        [self pushArgv:@"-device"];
        [self pushArgv:@"usb-ehci"];
        [self pushArgv:@"-device"];
        [self pushArgv:@"usb-tablet"];
    }
    if (self.snapshot) {
        [self pushArgv:@"-loadvm"];
        [self pushArgv:self.snapshot];
    }
    
    if (self.configuration.systemArguments.count != 0) {
        NSArray *addArgs = self.configuration.systemArguments;
        // Splits all spaces into their own, except when between quotes.
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\"[^\"]+\"|\\+|\\S+)" options:0 error:nil];
        
        for (NSString *arg in addArgs) {
            // No need to operate on empty arguments.
            if (arg.length == 0) {
                continue;
            }
            
            NSArray *splitArgsArray = [regex matchesInString:arg
                                              options:0
                                                range:NSMakeRange(0, [arg length])];
            
            
            for (NSTextCheckingResult *match in splitArgsArray) {
                NSRange matchRange = [match rangeAtIndex:1];
                NSString *argFragment = [arg substringWithRange:matchRange];
                [self pushArgv:argFragment];
            }
        }
    }
}

- (void)startWithCompletion:(void (^)(BOOL, NSString * _Nonnull))completion {
    NSString *dylib = [NSString stringWithFormat:@"libqemu-system-%@.dylib", self.configuration.systemArchitecture];
    [self argsFromConfiguration];
    [self startDylib:dylib main:@"qemu_main" completion:completion];
}

@end
