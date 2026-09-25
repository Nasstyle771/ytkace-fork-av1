#import "Hooking.h"

#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <string.h>
#import "../Features/Downloads/DownloadLog.h"

#include <os/lock.h>

static os_unfair_lock s_hookLock = OS_UNFAIR_LOCK_INIT;

static NSMutableSet<NSString *> *YTKACEHookKeys(void) {
    static NSMutableSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSMutableSet set];
    });
    return keys;
}

static NSMutableDictionary<NSString *, NSValue *> *YTKACEOriginalIMPs(void) {
    static NSMutableDictionary<NSString *, NSValue *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = [NSMutableDictionary dictionary];
    });
    return map;
}

static BOOL YTKACEInstallHook(NSString *className,
                              NSString *selectorName,
                              BOOL classMethod,
                              IMP replacement,
                              IMP *originalStorage) {
    if (className.length == 0 || selectorName.length == 0 || replacement == NULL) {
        return NO;
    }

    Class cls = NSClassFromString(className);
    if (cls == Nil) {
        return NO;
    }

    Class targetClass = classMethod ? object_getClass(cls) : cls;
    if (targetClass == Nil) {
        return NO;
    }

    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(targetClass, selector);
    if (method == NULL) {
        return NO;
    }

    NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                     className,
                     classMethod ? @"+" : @"-",
                     selectorName];

    os_unfair_lock_lock(&s_hookLock);
    if ([YTKACEHookKeys() containsObject:key]) {
        if (originalStorage != NULL && *originalStorage == NULL) {
            NSValue *val = YTKACEOriginalIMPs()[key];
            if (val != nil) {
                *originalStorage = (IMP)[val pointerValue];
            }
        }
        os_unfair_lock_unlock(&s_hookLock);
        return YES;
    }

    IMP original = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);

    BOOL added = class_addMethod(targetClass, selector, replacement, types);
    if (!added) {
        Method directMethod = class_getInstanceMethod(targetClass, selector);
        if (directMethod == NULL) {
            os_unfair_lock_unlock(&s_hookLock);
            return NO;
        }
        IMP prev = method_setImplementation(directMethod, replacement);
        if (prev != NULL) {
            original = prev;
        }
    }

    if (originalStorage != NULL) {
        *originalStorage = original;
    }
    if (original != NULL) {
        YTKACEOriginalIMPs()[key] = [NSValue valueWithPointer:(const void *)original];
    }
    [YTKACEHookKeys() addObject:key];
    os_unfair_lock_unlock(&s_hookLock);
    return YES;
}

BOOL YTKACEInstallInstanceHook(NSString *className,
                               NSString *selectorName,
                               IMP replacement,
                               IMP *originalStorage) {
    return YTKACEInstallHook(className, selectorName, NO, replacement, originalStorage);
}

BOOL YTKACEInstallClassHook(NSString *className,
                            NSString *selectorName,
                            IMP replacement,
                            IMP *originalStorage) {
    return YTKACEInstallHook(className, selectorName, YES, replacement, originalStorage);
}

BOOL YTKACEAddInstanceMethod(NSString *className,
                             NSString *selectorName,
                             IMP implementation,
                             const char *typeEncoding) {
    if (className.length == 0 || selectorName.length == 0 ||
        implementation == NULL || typeEncoding == NULL) {
        return NO;
    }

    Class cls = NSClassFromString(className);
    if (cls == Nil) {
        return NO;
    }

    NSString *key = [NSString stringWithFormat:@"%@|add|%@", className, selectorName];
    os_unfair_lock_lock(&s_hookLock);
    if ([YTKACEHookKeys() containsObject:key]) {
        os_unfair_lock_unlock(&s_hookLock);
        return YES;
    }

    BOOL added = class_addMethod(cls,
                                 NSSelectorFromString(selectorName),
                                 implementation,
                                 typeEncoding);
    if (added) {
        [YTKACEHookKeys() addObject:key];
        [YTKACEHookKeys() addObject:
            [NSString stringWithFormat:@"%@|-|%@", className, selectorName]];
    }
    os_unfair_lock_unlock(&s_hookLock);
    return added;
}

NSUInteger YTKACEInstalledHookCount(void) {
    os_unfair_lock_lock(&s_hookLock);
    NSUInteger count = YTKACEHookKeys().count;
    os_unfair_lock_unlock(&s_hookLock);
    return count;
}

typedef struct {
    void *isa;
    void *superclass;
    void *cacheBuckets;
    void *cacheMask;
    uintptr_t bits;
} YTKACEClassLayout;

static const uintptr_t YTKACESwiftFlags = 3;
static const uintptr_t YTKACEDataMask = 0x00007ffffffffff8UL;
static const uint32_t YTKACERealizedFlag = 1u << 31;

static const char *YTKACESafeClassName(Class cls) {
    if (cls == Nil) return NULL;
    const uintptr_t bits =
        ((const YTKACEClassLayout *)(__bridge const void *)cls)->bits;
    if (bits & YTKACESwiftFlags) return NULL;
    const uintptr_t data = bits & YTKACEDataMask;
    if (data == 0) return NULL;
    if (*(const uint32_t *)data & YTKACERealizedFlag) {
        return class_getName(cls);
    }
    return *(const char *const *)(data + 24);
}

static void YTKACECollectSection(const struct mach_header *header,
                                 const char *segment,
                                 NSMutableArray<NSString *> *names) {
    unsigned long size = 0;
    void *section = getsectiondata(
        (const struct mach_header_64 *)header, segment, "__objc_classlist", &size);
    if (section == NULL) return;
    uintptr_t *list = (uintptr_t *)section;
    for (unsigned long index = 0; index < size / sizeof(uintptr_t); index++) {
        const char *name =
            YTKACESafeClassName((__bridge Class)(void *)list[index]);
        if (name == NULL) continue;
        if (strncmp(name, "_Tt", 3) == 0) continue;
        if (strstr(name, "$s") != NULL) continue;
        NSString *value = [NSString stringWithUTF8String:name];
        if (value.length != 0) [names addObject:value];
    }
}

NSArray<NSString *> *YTKACEAppClassNames(void) {
    static NSArray<NSString *> *cachedNames = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        const uint32_t imageCount = _dyld_image_count();
        for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
            const char *path = _dyld_get_image_name(imageIndex);
            if (path == NULL) continue;
            if (strstr(path, "/System/") != NULL) continue;
            if (strstr(path, "/usr/lib/") != NULL) continue;
            const struct mach_header *header = _dyld_get_image_header(imageIndex);
            if (header == NULL) continue;
            YTKACECollectSection(header, "__DATA_CONST", names);
            YTKACECollectSection(header, "__AUTH_CONST", names);
            YTKACECollectSection(header, "__DATA", names);
        }
        cachedNames = [names copy];
        YTKACEDownloadLog(@"scan", @"%lu objc classes across %u images",
                          (unsigned long)cachedNames.count, imageCount);
    });
    return cachedNames;
}
