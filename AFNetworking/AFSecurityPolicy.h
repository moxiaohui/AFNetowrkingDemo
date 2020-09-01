// AFSecurityPolicy.h
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

#import <Foundation/Foundation.h>
#import <Security/Security.h>

typedef NS_ENUM(NSUInteger, AFSSLPinningMode) {
    AFSSLPinningModeNone, //mo: 在系统的信任的证书列表中对服务端返回的证书进行验证
    AFSSLPinningModePublicKey, //mo: 客户端需要有证书, 代表会对服务器返回的证书中的PublicKey(公钥)进行验证
    AFSSLPinningModeCertificate, //mo: 客户端需要有证书, 先验证证书域名/有效期等信息，然后验证服务端返回的证书和本地的是否一致
};

/**
 `AFSecurityPolicy` evaluates server trust against pinned X.509 certificates and public keys over secure connections.

 Adding pinned SSL certificates to your app helps prevent man-in-the-middle attacks and other vulnerabilities. Applications dealing with sensitive customer data or financial information are strongly encouraged to route all communication over an HTTPS connection with SSL pinning configured and enabled.
 */

NS_ASSUME_NONNULL_BEGIN

@interface AFSecurityPolicy : NSObject <NSSecureCoding, NSCopying>

/**
 The criteria by which server trust should be evaluated against the pinned SSL certificates. Defaults to `AFSSLPinningModeNone`.
 */
@property (readonly, nonatomic, assign) AFSSLPinningMode SSLPinningMode;

/** mo: 保存着所有的可用做校验的证书的集合。
 AFNetworking默认会搜索工程中所有.cer的证书文件。
 如果想制定某些证书，可使用certificatesInBundle在目标路径下加载证书，然后调用policyWithPinningMode:withPinnedCertificates创建一个本类对象。

 The certificates used to evaluate server trust according to the SSL pinning mode. 
 
 Note that if pinning is enabled, `evaluateServerTrust:forDomain:` will return true if any pinned certificate matches.

 @see policyWithPinningMode:withPinnedCertificates:
 */
@property (nonatomic, strong, nullable) NSSet <NSData *> *pinnedCertificates;

/**
 mo: 是否允许使用无效或过期的证书,包括自建证书，默认是不允许。
 Whether or not to trust servers with an invalid or expired SSL certificates. Defaults to `NO`.
 */
@property (nonatomic, assign) BOOL allowInvalidCertificates;

/**
 mo: 是否验证证书中的域名domain 默认YES
 Whether or not to validate the domain name in the certificate's CN field. Defaults to `YES`.
 */
@property (nonatomic, assign) BOOL validatesDomainName;

///-----------------------------------------
/// @name Getting Certificates from the Bundle
///-----------------------------------------

/**
 mo: 返回指定bundle中的证书
 Returns any certificates included in the bundle. If you are using AFNetworking as an embedded framework, you must use this method to find the certificates you have included in your app bundle, and use them when creating your security policy by calling `policyWithPinningMode:withPinnedCertificates`.

 @return The certificates included in the given bundle.
 */
+ (NSSet <NSData *> *)certificatesInBundle:(NSBundle *)bundle;

///-----------------------------------------
/// @name Getting Specific Security Policies
///-----------------------------------------

/** 初始化方法1
 mo: 默认的实例对象，默认的认证设置为
 1. 不允许无效或过期的证书
 2. 验证domain主机名称
 3. 不对证书和公钥进行验证
 
 Returns the shared default security policy, which does not allow invalid certificates, validates domain name, and does not validate against pinned certificates or public keys.

 @return The default security policy.
 */
+ (instancetype)defaultPolicy;

///---------------------
/// @name Initialization
///---------------------

/** 初始化方法2
 mo: 根据指定的认证策略和默认的证书列表(Bundle的所有.cer文件)初始化一个AFSecurityPolicy对象
 Creates and returns a security policy with the specified pinning mode.
 
 Certificates with the `.cer` extension found in the main bundle will be pinned. If you want more control over which certificates are pinned, please use `policyWithPinningMode:withPinnedCertificates:` instead.

 @param pinningMode The SSL pinning mode.

 @return A new security policy.

 @see -policyWithPinningMode:withPinnedCertificates:
 */
+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode;

/** 初始化方法3
 mo: 过制定的认证策略pinningMode和证书集合pinnedCertificates来初始化一个AFSecurityPolicy对象
 Creates and returns a security policy with the specified pinning mode.

 @param pinningMode The SSL pinning mode.
 @param pinnedCertificates The certificates to pin against.

 @return A new security policy.

 @see +certificatesInBundle:
 @see -pinnedCertificates
*/
+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode withPinnedCertificates:(NSSet <NSData *> *)pinnedCertificates;

///------------------------------
/// @name Evaluating Server Trust
///------------------------------

/**
 Whether or not the specified server trust should be accepted, based on the security policy.

 This method should be used when responding to an authentication challenge from a server.

 @param serverTrust The X.509 certificate trust of the server.
 @param domain The domain of serverTrust. If `nil`, the domain will not be validated.

 @return Whether or not to trust the server.
 */
- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(nullable NSString *)domain;

@end

NS_ASSUME_NONNULL_END

///----------------
/// @name Constants
///----------------

/**
 ## SSL Pinning Modes

 The following constants are provided by `AFSSLPinningMode` as possible SSL pinning modes.

 enum {
 AFSSLPinningModeNone,
 AFSSLPinningModePublicKey,
 AFSSLPinningModeCertificate,
 }

 `AFSSLPinningModeNone`
 Do not used pinned certificates to validate servers.

 `AFSSLPinningModePublicKey`
 Validate host certificates against public keys of pinned certificates.

 `AFSSLPinningModeCertificate`
 Validate host certificates against pinned certificates.
*/
