// AFSecurityPolicy.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFSecurityPolicy.h"
#import <AssertMacros.h>

#if !TARGET_OS_IOS && !TARGET_OS_WATCH && !TARGET_OS_TV
static NSData * AFSecKeyGetData(SecKeyRef key) {
    CFDataRef data = NULL;
    __Require_noErr_Quiet(SecItemExport(key, kSecFormatUnknown, kSecItemPemArmour, NULL, &data), _out);
    return (__bridge_transfer NSData *)data;
_out:
    if (data) {
        CFRelease(data);
    }
    return nil;
}
#endif

static BOOL AFSecKeyIsEqualToKey(SecKeyRef key1, SecKeyRef key2) {
#if TARGET_OS_IOS || TARGET_OS_WATCH || TARGET_OS_TV
    return [(__bridge id)key1 isEqual:(__bridge id)key2];
#else
    return [AFSecKeyGetData(key1) isEqual:AFSecKeyGetData(key2)];
#endif
}

#pragma mark - mo: 在证书中获取公钥
static id AFPublicKeyForCertificate(NSData *certificate) {
    id allowedPublicKey = nil;
    SecCertificateRef allowedCertificate;
    SecPolicyRef policy = nil;
    SecTrustRef allowedTrust = nil;
    SecTrustResultType result;
    //mo: 根据data生成证书
    allowedCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificate); // NSData -> CFDataRef
    //mo: 当条件返回false时, 跳转到 _out
    __Require_Quiet(allowedCertificate != NULL, _out);
    policy = SecPolicyCreateBasicX509(); //mo: X.509政策对象
    
    //mo: __Require_noErr_Quiet: 如果出错, 则跳转到 _out
    /* 根据证书和政策创建一个信任管理对象
     certificates: 要认证的证书+你认为对证书有用的任何其他证书
     policies: 参考评估政策
     trust: 返回时, 指向新创建的信任管理对象
     */
    __Require_noErr_Quiet(SecTrustCreateWithCertificates(allowedCertificate, policy, &allowedTrust), _out);
    //mo: 忽略弃用警告
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    //mo: 评估指定 证书 和 策略 的信任 (同步的)
    __Require_noErr_Quiet(SecTrustEvaluate(allowedTrust, &result), _out);
#pragma clang diagnostic pop
    //mo: 在`叶证书`求值后返回其公钥
    allowedPublicKey = (__bridge_transfer id)SecTrustCopyPublicKey(allowedTrust);

_out:
    if (allowedTrust) {
        CFRelease(allowedTrust);
    }
    if (policy) {
        CFRelease(policy);
    }
    if (allowedCertificate) {
        CFRelease(allowedCertificate);
    }
    return allowedPublicKey;
}

#pragma mark - mo: 证书评估
static BOOL AFServerTrustIsValid(SecTrustRef serverTrust) {
    BOOL isValid = NO;
    SecTrustResultType result;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    //mo: 评估指定 证书 和 策略 的信任 (同步的)
    __Require_noErr_Quiet(SecTrustEvaluate(serverTrust, &result), _out);
#pragma clang diagnostic pop
    //mo: 判断是否验证成功
    // kSecTrustResultUnspecified: 表示 serverTrust验证成功，此证书被暗中信任了，但是用户并没有显示地决定信任该证书
    // kSecTrustResultProceed: 表示serverTrust验证成功，且该验证得到了用户认可(例如在弹出的是否信任的alert框中选择always trust)
    isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
_out:
    return isValid;
}

#pragma mark - mo: 获取到`serverTrust`中证书链上的所有证书
static NSArray * AFCertificateTrustChainForServerTrust(SecTrustRef serverTrust) {
    //mo: 使用SecTrustGetCertificateCount函数获取serverTrust中需要评估的证书链中的证书数目，并保存到certificateCount中
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    //mo: 使用SecTrustGetCertificateAtIndex函数获取到证书链中的每个证书，并添加到trustChain中，最后返回trustChain
    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        [trustChain addObject:(__bridge_transfer NSData *)SecCertificateCopyData(certificate)];
    }
    return [NSArray arrayWithArray:trustChain];
}

#pragma mark - mo: 取出`serverTrust`中证书链上每个证书的公钥，并返回对应的该组公钥
static NSArray * AFPublicKeyTrustChainForServerTrust(SecTrustRef serverTrust) {
    SecPolicyRef policy = SecPolicyCreateBasicX509(); //mo: X.509标准的安全策略
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust); //mo: 获取证书链的证书数量
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);

        SecCertificateRef someCertificates[] = {certificate};
        CFArrayRef certificates = CFArrayCreate(NULL, (const void **)someCertificates, 1, NULL);

        SecTrustRef trust;
        //mo: 根据给定的certificates和policy来生成一个trust对象
        __Require_noErr_Quiet(SecTrustCreateWithCertificates(certificates, policy, &trust), _out);
        SecTrustResultType result;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        //mo: 使用SecTrustEvaluate来评估上面构建的trust
        __Require_noErr_Quiet(SecTrustEvaluate(trust, &result), _out);
#pragma clang diagnostic pop
        //mo: 如果该trust符合X.509证书格式，那么先使用SecTrustCopyPublicKey获取到trust的公钥，再将此公钥添加到trustChain中
        [trustChain addObject:(__bridge_transfer id)SecTrustCopyPublicKey(trust)];

    _out:
        if (trust) {
            CFRelease(trust);
        }
        if (certificates) {
            CFRelease(certificates);
        }
        continue;
    }
    CFRelease(policy);
    //mo: 返回对应的一组公钥
    return [NSArray arrayWithArray:trustChain];
}

#pragma mark -
@interface AFSecurityPolicy()
@property (readwrite, nonatomic, assign) AFSSLPinningMode SSLPinningMode;
@property (readwrite, nonatomic, strong) NSSet *pinnedPublicKeys;
@end

@implementation AFSecurityPolicy

//mo: 获得bundle里的以`.cer`结尾的所有证书
+ (NSSet *)certificatesInBundle:(NSBundle *)bundle {
    NSArray *paths = [bundle pathsForResourcesOfType:@"cer" inDirectory:@"."];
    NSMutableSet *certificates = [NSMutableSet setWithCapacity:[paths count]];
    for (NSString *path in paths) {
        NSData *certificateData = [NSData dataWithContentsOfFile:path];
        [certificates addObject:certificateData];
    }
    return [NSSet setWithSet:certificates];
}

+ (instancetype)defaultPolicy {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = AFSSLPinningModeNone;
    return securityPolicy;
}

+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode {
    NSSet <NSData *> *defaultPinnedCertificates = [self certificatesInBundle:[NSBundle mainBundle]]; //mo: 所有证书
    return [self policyWithPinningMode:pinningMode withPinnedCertificates:defaultPinnedCertificates];
}

+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode withPinnedCertificates:(NSSet *)pinnedCertificates {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = pinningMode;
    [securityPolicy setPinnedCertificates:pinnedCertificates];
    return securityPolicy;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    self.validatesDomainName = YES;
    return self;
}

- (void)setPinnedCertificates:(NSSet *)pinnedCertificates {
    _pinnedCertificates = pinnedCertificates;
    if (self.pinnedCertificates) {
        //mo: 遍历证书获取公钥
        NSMutableSet *mutablePinnedPublicKeys = [NSMutableSet setWithCapacity:[self.pinnedCertificates count]];
        for (NSData *certificate in self.pinnedCertificates) {
            id publicKey = AFPublicKeyForCertificate(certificate); //mo: 在证书中获取公钥
            if (!publicKey) {
                continue;
            }
            [mutablePinnedPublicKeys addObject:publicKey];
        }
        self.pinnedPublicKeys = [NSSet setWithSet:mutablePinnedPublicKeys];
    } else {
        self.pinnedPublicKeys = nil;
    }
}

#pragma mark - mo: 是否应根据安全策略接受指定的服务器信任, 在响应来自服务器的身份验证质询时应使用此方法
// mo: 核心方法
- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain {
    //mo: 表示如果此处允许使用自建证书（服务器自己弄的CA证书，非官方），并且还想验证domain是否有效(self.validatesDomainName == YES)，也就是说你想验证自建证书的domain是否有效。那么你必须使用pinnedCertificates（就是在客户端保存服务器端颁发的证书拷贝）才可以。但是你的SSLPinningMode为AFSSLPinningModeNone，表示你不使用SSL pinning，只跟浏览器一样在系统的信任机构列表里验证服务端返回的证书。所以当你的客户端上没有你导入的pinnedCertificates，同样表示你无法验证该自建证书。所以都返回NO。最终结论就是要使用服务器端自建证书，那么就得将对应的证书拷贝到iOS客户端，并使用AFSSLPinningModeCertificate或AFSSLPinningModePublicKey
    if (domain && self.allowInvalidCertificates && self.validatesDomainName && (self.SSLPinningMode == AFSSLPinningModeNone || [self.pinnedCertificates count] == 0)) {
        // https://developer.apple.com/library/mac/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/OverridingSSLChainValidationCorrectly.html
        //  According to the docs, you should only trust your provided certs for evaluation.
        //  Pinned certificates are added to the trust. Without pinned certificates,
        //  there is nothing to evaluate against.
        //
        //  From Apple Docs:
        //          "Do not implicitly trust self-signed certificates as anchors (kSecTrustOptionImplicitAnchors).
        //           Instead, add your own (self-signed) CA certificate to the list of trusted anchors."
        NSLog(@"In order to validate a domain name for self signed certificates, you MUST use pinning.");
        return NO;
    }

    NSMutableArray *policies = [NSMutableArray array];
    
    if (self.validatesDomainName) { //mo: 是否需要验证domain
        //mo: 评估SSL证书链的策略对象
        // 使用SecPolicyCreateSSL函数创建验证策略
        // 其中第一个参数为true表示验证整个SSL证书链，第二个参数传入domain，用于判断整个证书链上叶子节点表示的那个domain是否和此处传入domain一致
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        //mo: 如果不需要验证domain，就使用默认的BasicX509验证策略
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
    }

    //mo: 为serverTrust设置验证策略，即告诉客户端如何验证serverTrust
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);

    if (self.SSLPinningMode == AFSSLPinningModeNone) {
        // 不需要验证 || 评估证书
        return self.allowInvalidCertificates || AFServerTrustIsValid(serverTrust);
    } else if (!self.allowInvalidCertificates && !AFServerTrustIsValid(serverTrust)) {
        // 否则 需要验证 && 没有验证通过 则返回失败
        return NO;
    }

    switch (self.SSLPinningMode) {
        case AFSSLPinningModeCertificate: {
            NSMutableArray *pinnedCertificates = [NSMutableArray array];
            for (NSData *certificateData in self.pinnedCertificates) {
                // 根据data生成证书
                [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
            }
            /* mo: 设置评估信任管理对象时使用的定位证书。
             trust: 包含要评估的证书 的信任管理对象
             anchorCertificates: 参考证书
             */
            SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);

            if (!AFServerTrustIsValid(serverTrust)) {
                return NO;
            }

            // obtain the chain after being validated, which *should* contain the pinned certificate in the last position (if it's the Root CA)
            //mo: 获取到 serverTrust 中证书链上的所有证书, 注意: 此处返回的证书链顺序是从叶节点到根节点
            NSArray *serverCertificates = AFCertificateTrustChainForServerTrust(serverTrust);
            //mo: 从服务器端证书链的根节点往下遍历，看看是否有与客户端的绑定证书一致的，有的话，就说明服务器端是可信的。
            //mo: 因为遍历顺序正好相反，所以使用 reverseObjectEnumerator
            for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {
                if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
                    return YES;
                }
            }
            return NO;
        }
        case AFSSLPinningModePublicKey: {
            NSUInteger trustedPublicKeyCount = 0;
            //mo: 从`serverTrust`中取出服务器端传过来的所有可用的证书，并依次得到相应的公钥
            NSArray *publicKeys = AFPublicKeyTrustChainForServerTrust(serverTrust);
            //mo: 依次遍历这些公钥，如果和客户端绑定证书的公钥一致，那么就给`trustedPublicKeyCount`加一
            for (id trustChainPublicKey in publicKeys) {
                for (id pinnedPublicKey in self.pinnedPublicKeys) {
                    if (AFSecKeyIsEqualToKey((__bridge SecKeyRef)trustChainPublicKey, (__bridge SecKeyRef)pinnedPublicKey)) {
                        trustedPublicKeyCount += 1;
                    }
                }
            }
            //mo: 大于0说明服务器端中的某个证书和客户端绑定的证书公钥一致，认为服务器端是可信的
            return trustedPublicKeyCount > 0;
        }
        default: return NO;
    }
    return NO;
}

#pragma mark - NSKeyValueObserving
+ (NSSet *)keyPathsForValuesAffectingPinnedPublicKeys {
    return [NSSet setWithObject:@"pinnedCertificates"];
}

#pragma mark - NSSecureCoding
+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
    self = [self init];
    if (!self) {
        return nil;
    }
    self.SSLPinningMode = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(SSLPinningMode))] unsignedIntegerValue];
    self.allowInvalidCertificates = [decoder decodeBoolForKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
    self.validatesDomainName = [decoder decodeBoolForKey:NSStringFromSelector(@selector(validatesDomainName))];
    self.pinnedCertificates = [decoder decodeObjectOfClass:[NSSet class] forKey:NSStringFromSelector(@selector(pinnedCertificates))];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:[NSNumber numberWithUnsignedInteger:self.SSLPinningMode] forKey:NSStringFromSelector(@selector(SSLPinningMode))];
    [coder encodeBool:self.allowInvalidCertificates forKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
    [coder encodeBool:self.validatesDomainName forKey:NSStringFromSelector(@selector(validatesDomainName))];
    [coder encodeObject:self.pinnedCertificates forKey:NSStringFromSelector(@selector(pinnedCertificates))];
}

#pragma mark - NSCopying
- (instancetype)copyWithZone:(NSZone *)zone {
    AFSecurityPolicy *securityPolicy = [[[self class] allocWithZone:zone] init];
    securityPolicy.SSLPinningMode = self.SSLPinningMode;
    securityPolicy.allowInvalidCertificates = self.allowInvalidCertificates;
    securityPolicy.validatesDomainName = self.validatesDomainName;
    securityPolicy.pinnedCertificates = [self.pinnedCertificates copyWithZone:zone];
    return securityPolicy;
}

@end
