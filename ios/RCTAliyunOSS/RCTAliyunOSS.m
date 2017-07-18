//
//  RCTAliyunOSS.m
//  RCTAliyunOSS
//
//  Created by 李京生 on 2016/10/26.
//  Copyright © 2016年 lesonli. All rights reserved.
//

#import "RCTAliyunOSS.h"
#import "RCTLog.h"
#import "OSSService.h"


@implementation RCTAliyunOSS{
    
    OSSClient *client;
 
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"uploadProgress", @"downloadProgress", @"getBuckerFiles", @"esumableUploadProgress",@"checkObjectExist"];
}

// get local file dir which is readwrite able
- (NSString *)getDocumentDirectory {
    NSString * path = NSHomeDirectory();
    NSLog(@"NSHomeDirectory:%@",path);
    NSString * userName = NSUserName();
    NSString * rootPath = NSHomeDirectoryForUser(userName);
    NSLog(@"NSHomeDirectoryForUser:%@",rootPath);
    NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString * documentsDirectory = [paths objectAtIndex:0];
    return documentsDirectory;
}

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(enableOSSLog) {
    // 打开调试log
    [OSSLog enableLog];
    RCTLogInfo(@"OSSLog: 已开启");
}
// 由阿里云颁发的AccessKeyId/AccessKeySecret初始化客户端。
// 明文设置secret的方式建议只在测试时使用，
// 如果已经在bucket上绑定cname，将该cname直接设置到endPoint即可
RCT_EXPORT_METHOD(initWithKey:(NSString *)AccessKey
                  SecretKey:(NSString *)SecretKey
                  securityToken:(NSString *)securityToken
                  Endpoint:(NSString *)Endpoint){
    
    id<OSSCredentialProvider> credential = [[OSSStsTokenCredentialProvider alloc] initWithAccessKeyId:AccessKey secretKeyId:SecretKey securityToken:securityToken];
    
    //bucket上绑定cname，将该cname直接设置到endPoint
    OSSClientConfiguration * conf = [OSSClientConfiguration new];
    conf.maxRetryCount = 3; // 网络请求遇到异常失败后的重试次数
    conf.timeoutIntervalForRequest = 30; // 网络请求的超时时间
    conf.timeoutIntervalForResource = 24 * 60 * 60; // 允许资源传输的最长时间
    NSString *endpoint = Endpoint;
    
    client = [[OSSClient alloc] initWithEndpoint:endpoint credentialProvider:credential clientConfiguration:conf];
}

//通过签名方式初始化，需要服务端实现签名字符串，签名算法参考阿里云文档
RCT_EXPORT_METHOD(initWithSigner:(NSString *)AccessKey
                  Signature:(NSString *)Signature
                  Endpoint:(NSString *)Endpoint){
    
    // 自实现签名，可以用本地签名也可以远程加签
    id<OSSCredentialProvider> credential1 = [[OSSCustomSignerCredentialProvider alloc] initWithImplementedSigner:^NSString *(NSString *contentToSign, NSError *__autoreleasing *error) {
        //NSString *signature = [OSSUtil calBase64Sha1WithData:contentToSign withSecret:@"<your secret key>"];
        if (Signature != nil) {
            *error = nil;
        } else {
            // construct error object
            *error = [NSError errorWithDomain:Endpoint code:OSSClientErrorCodeSignFailed userInfo:nil];
            return nil;
        }
        //return [NSString stringWithFormat:@"OSS %@:%@", @"<your access key>", signature];
        return [NSString stringWithFormat:@"OSS %@:%@", AccessKey, Signature];
    }];

    
    OSSClientConfiguration * conf = [OSSClientConfiguration new];
    conf.maxRetryCount = 1;
    conf.timeoutIntervalForRequest = 30;
    conf.timeoutIntervalForResource = 24 * 60 * 60;
    
    client = [[OSSClient alloc] initWithEndpoint:Endpoint credentialProvider:credential1 clientConfiguration:conf];
}

//异步下载
RCT_REMAP_METHOD(downloadObjectAsync, bucketName:(NSString *)bucketName objectKey:(NSString *)objectKey updateDate:(NSString *)updateDate resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    OSSGetObjectRequest *request = [OSSGetObjectRequest new];
    // required
    request.bucketName = bucketName;
    request.objectKey = objectKey;
    // optional
    request.downloadProgress = ^(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
        NSLog(@"%lld, %lld, %lld", bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
        [self sendEventWithName: @"downloadProgress" body:@{@"everySentSize":[NSString stringWithFormat:@"%lld",bytesWritten],
                                                          @"currentSize": [NSString stringWithFormat:@"%lld",totalBytesWritten],
                                                          @"totalSize": [NSString stringWithFormat:@"%lld",totalBytesExpectedToWrite]}];
    };
    NSString *docDir = [self getDocumentDirectory];
    NSLog(objectKey);
    NSURL *url = [NSURL fileURLWithPath:[docDir stringByAppendingPathComponent:objectKey]];
    request.downloadToFileURL = url;
    OSSTask *getTask = [client getObject:request];
    [getTask continueWithBlock:^id(OSSTask *task) {
        if (!task.error) {
            NSLog(@"download object success!");
            OSSGetObjectResult *result = task.result;
            NSLog(@"download dota length: %lu", [result.downloadedData length]);
            resolve(url.absoluteString);
        } else {
            NSLog(@"download object failed, error: %@" ,task.error);
            reject(nil, @"download object failed", task.error);
        }
        return nil;
    }];
}

RCT_REMAP_METHOD(getBuckerFiles,bucketName:(NSString *)BucketName
                 file:(NSString *)file
                 maxkeys:(int)maxkeys
                 marker:(NSString *)marker
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject){
    OSSGetBucketRequest * getBucket = [OSSGetBucketRequest new];
    getBucket.bucketName = BucketName;
    getBucket.prefix = file;
    getBucket.maxKeys = maxkeys;
    
    OSSTask * getBucketTask = [client getBucket:getBucket];
    [getBucketTask continueWithBlock:^id(OSSTask *task) {
        if (!task.error) {
            
            OSSGetBucketResult * result = task.result;
            NSMutableArray *array = [[NSMutableArray alloc] init];
            for (NSDictionary * objectInfo in result.contents) {
//                NSLog(@"list object: %@", objectInfo);
//                NSLog(@"%@",[objectInfo valueForKey:@"Key"]);
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                [dict setObject:[objectInfo valueForKey:@"Key"] forKey:@"key"];
                [dict setObject:[objectInfo valueForKey:@"ETag"] forKey:@"eTag"];
                [dict setObject:[objectInfo valueForKey:@"LastModified"] forKey:@"lastModified"];
                [dict setObject:[NSNumber numberWithDouble:[[objectInfo valueForKey:@"Size"] doubleValue]] forKey:@"size"];
                //NSLog(@"%@",[objectInfo valueForKey:@"key"]);
//                NSDictionary *dict = @{@"key":[objectInfo valueForKey:@"key"],
//                                       @"eTag":[objectInfo valueForKey:@"eTag"],
//                                       @"lastModified":[objectInfo valueForKey:@"lastModified"],
//                                       @"size":[NSNumber numberWithDouble:[[objectInfo valueForKey:@"size"] doubleValue]]};
                NSLog(@"dict = %@",dict);
                [array addObject:dict];
            }
            NSString *nextMarker = nil;
            if (result.nextMarker == nil) {
                nextMarker = @"";
            }else{
                nextMarker = result.nextMarker;
            }
            NSLog(@"result.isTruncated = %d",result.isTruncated);
            [self sendEventWithName:@"getBuckerFiles" body:@{@"isTruncated":[NSNumber numberWithBool:result.isTruncated],
                                                             @"nextMarker":nextMarker,
                                                             @"buckerFiles":array}];
            
//            [self performSelectorOnMainThread:@selector(updateUI) withObject:nil waitUntilDone:YES];
            NSLog(@"get bucket success!");
            resolve(@"getBuckerFilesSuccess");
        } else {
//            [self performSelectorOnMainThread:@selector(updateUI) withObject:nil waitUntilDone:YES];
            NSLog(@"get bucket failed, error: %@", task.error);
            reject(@"-1", @"get bucket failed, error", task.error);
        }
        return nil;
    }];
}

//删除素材
RCT_REMAP_METHOD(deleteFile, bucketName:(NSString *)BucketName
                 objectKey:(NSString *)objectKey
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    OSSDeleteObjectRequest * delete = [OSSDeleteObjectRequest new];
    delete.bucketName = BucketName;
    delete.objectKey = objectKey;
    OSSTask * deleteTask = [client deleteObject:delete];
    [deleteTask continueWithBlock:^id(OSSTask *task) {
        if (!task.error) {
            // ...
            resolve(@"deleteFileSuccess");
        }else{
            reject(@"-1", @"deleteFileFaile", task.error);
        }
        return nil;
    }];
}

//判断是否已经上传
RCT_REMAP_METHOD(checkObjectExist, bucketName:(NSString *)BucketName
                 objectkey:(NSString *)objectkey
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject){
    bool exist = [client doesObjectExistInBucket:BucketName objectKey:objectkey error:nil];
    if (exist) {
        NSLog(@"object exist.");
    }else{
        NSLog(@"object does not exist.");
    }
    [self sendEventWithName: @"checkObjectExist" body:@{@"isObjectExist": [NSNumber numberWithBool:exist]}];
}

//异步断点上传
RCT_REMAP_METHOD(resumableUploadWithRecordPathSetting, bucketName:(NSString *)BucketName
                 sourceFile:(NSData *)sourceFile
                 OssFile:(NSString *)OssFile
                 needCallBack:(int)needCallBack
                 callbackUrl:(NSString *)callbackUrl
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject){
    
//    __block NSString * uploadId = nil;
//    __block NSMutableArray * partInfos = [NSMutableArray new];
//    
//    NSLog(@"SourceFile = %@",sourceFile);
//    NSLog(@"OssFile = %@",OssFile);
//    OSSInitMultipartUploadRequest * init = [OSSInitMultipartUploadRequest new];
//    init.bucketName = BucketName;
//    init.objectKey = OssFile;
//    init.contentType = @"application/octet-stream";
//    init.objectMeta = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"value1", @"x-oss-meta-name1", nil];
//    
//    OSSTask * initTask = [client multipartUploadInit:init];
//    [initTask waitUntilFinished];
//    
//    if (!initTask.error) {
//        OSSInitMultipartUploadResult * result = initTask.result;
//        uploadId = result.uploadId;
//        NSLog(@"init multipart upload success: %@", result.uploadId);
//    } else {
//        NSLog(@"multipart upload failed, error: %@", initTask.error);
//        return;
//    }
//    
//    for (int i = 1; i <= 20; i++) {
//        @autoreleasepool {
//            OSSUploadPartRequest * uploadPart = [OSSUploadPartRequest new];
//            uploadPart.bucketName = BucketName;
//            uploadPart.objectkey = OssFile;
//            uploadPart.uploadId = uploadId;
//            uploadPart.partNumber = i; // part number start from 1
//            uploadPart.uploadPartProgress = ^(int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
//                [self sendEventWithName: @"esumableUploadProgress" body:@{@"currentSize": [NSString stringWithFormat:@"%lld",totalBytesSent],
//                                                                  @"totalSize": [NSString stringWithFormat:@"%lld",totalBytesExpectedToSend]}];
//            };
//            NSString * docDir = [self getDocumentDirectory];
//            // uploadPart.uploadPartFileURL = [NSURL URLWithString:[docDir stringByAppendingPathComponent:@"file1m"]];
////            uploadPart.uploadPartData = [NSData dataWithContentsOfFile:[docDir stringByAppendingPathComponent:@"file1m"]];
//            uploadPart.uploadPartData = sourceFile;
//            
//            OSSTask * uploadPartTask = [client uploadPart:uploadPart];
//            
//            [uploadPartTask waitUntilFinished];
//            
//            if (!uploadPartTask.error) {
//                OSSUploadPartResult * result = uploadPartTask.result;
//                uint64_t fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:uploadPart.uploadPartFileURL.absoluteString error:nil] fileSize];
//                [partInfos addObject:[OSSPartInfo partInfoWithPartNum:i eTag:result.eTag size:fileSize]];
//            } else {
//                NSLog(@"upload part error: %@", uploadPartTask.error);
//                return;
//            }
//        }
//    }
//    
//    OSSCompleteMultipartUploadRequest * complete = [OSSCompleteMultipartUploadRequest new];
//    complete.bucketName = BucketName;
//    complete.objectKey = OssFile;
//    complete.uploadId = uploadId;
//    complete.partInfos = partInfos;
//    
//    complete.callbackParam = @{
//                               @"callbackUrl": callbackUrl,
//                               @"callbackBody": [NSString stringWithFormat:@"filename=%@",OssFile]
//                               };
////    complete.callbackVar = @{
////                             @"var1": @"value1",
////                             @"var2": @"value2"
////                             };
//    
//    OSSTask * completeTask = [client completeMultipartUpload:complete];
//    
//    [completeTask waitUntilFinished];
//    
//    if (!completeTask.error) {
//        NSLog(@"multipart upload success!");
//    } else {
//        NSLog(@"multipart upload failed, error: %@", completeTask.error);
//        return;
//    }
    
    
    OSSPutObjectRequest * put = [OSSPutObjectRequest new];
    
    // required fields
    put.bucketName = BucketName;
    put.objectKey = OssFile;
    //NSString * docDir = [self getDocumentDirectory];
    //put.uploadingFileURL = [NSURL fileURLWithPath:[docDir stringByAppendingPathComponent:@"file1m"]];
    put.uploadingData = sourceFile;
    NSLog(@"uploadingFileURL: %@", put.uploadingFileURL);
    // optional fields
    put.uploadProgress = ^(int64_t bytesSent, int64_t totalByteSent, int64_t totalBytesExpectedToSend) {
        NSLog(@"%lld, %lld, %lld", bytesSent, totalByteSent, totalBytesExpectedToSend);
        [self sendEventWithName: @"esumableUploadProgress" body:@{@"currentSize": [NSString stringWithFormat:@"%lld",totalByteSent],@"totalSize": [NSString stringWithFormat:@"%lld",totalBytesExpectedToSend]}];
        
    };
    //put.contentType = @"";
    //put.contentMd5 = @"";
    //put.contentEncoding = @"";
    //put.contentDisposition = @"";
//    put.objectMeta = [NSMutableDictionary dictionaryWithObjectsAndKeys: UpdateDate, @"Date", nil];
    
    OSSTask * putTask = [client putObject:put];
    
    [putTask continueWithBlock:^id(OSSTask *task) {
        NSLog(@"objectKey: %@", put.objectKey);
        if (!task.error) {
            NSLog(@"upload object success!");
            resolve(@YES);
        } else {
            NSLog(@"upload object failed, error: %@" , task.error);
            reject(@"-1", @"not respond this method", nil);
        }
        return nil;
    }];
    
}

//异步上传
RCT_REMAP_METHOD(uploadObjectAsync, bucketName:(NSString *)BucketName
                  SourceFile:(NSString *)SourceFile
                  OssFile:(NSString *)OssFile
                  UpdateDate:(NSString *)UpdateDate
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    OSSPutObjectRequest * put = [OSSPutObjectRequest new];
    
    // required fields
    put.bucketName = BucketName;
    put.objectKey = OssFile;
    //NSString * docDir = [self getDocumentDirectory];
    //put.uploadingFileURL = [NSURL fileURLWithPath:[docDir stringByAppendingPathComponent:@"file1m"]];
    put.uploadingFileURL = [NSURL fileURLWithPath:SourceFile];
    NSLog(@"uploadingFileURL: %@", put.uploadingFileURL);
    // optional fields
    put.uploadProgress = ^(int64_t bytesSent, int64_t totalByteSent, int64_t totalBytesExpectedToSend) {
        NSLog(@"%lld, %lld, %lld", bytesSent, totalByteSent, totalBytesExpectedToSend);
        [self sendEventWithName: @"uploadProgress" body:@{@"everySentSize":[NSString stringWithFormat:@"%lld",bytesSent],
                                                          @"currentSize": [NSString stringWithFormat:@"%lld",totalByteSent],
                                                          @"totalSize": [NSString stringWithFormat:@"%lld",totalBytesExpectedToSend]}];

    };
    //put.contentType = @"";
    //put.contentMd5 = @"";
    //put.contentEncoding = @"";
    //put.contentDisposition = @"";
     put.objectMeta = [NSMutableDictionary dictionaryWithObjectsAndKeys: UpdateDate, @"Date", nil];
    
    OSSTask * putTask = [client putObject:put];
    
    [putTask continueWithBlock:^id(OSSTask *task) {
        NSLog(@"objectKey: %@", put.objectKey);
        if (!task.error) {
            NSLog(@"upload object success!");
            resolve(@YES);
        } else {
            NSLog(@"upload object failed, error: %@" , task.error);
            reject(@"-1", @"not respond this method", nil);
        }
        return nil;
    }];
}



@end
