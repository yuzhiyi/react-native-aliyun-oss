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
    OSSResumableUploadRequest *mresumableUpload;
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"uploadProgress", @"downloadProgress", @"getBuckerFiles", @"esumableUploadProgress",@"checkObjectExist",@"resumableUploadSuccess",@"resumableUploadFail"];
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
    getBucket.marker = marker;

    OSSTask * getBucketTask = [client getBucket:getBucket];
    [getBucketTask continueWithBlock:^id(OSSTask *task) {
        if (!task.error) {

            OSSGetBucketResult * result = task.result;
            NSMutableArray *array = [[NSMutableArray alloc] init];
            for (NSDictionary * objectInfo in result.contents) {
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                [dict setObject:[objectInfo valueForKey:@"Key"] forKey:@"key"];
                [dict setObject:[objectInfo valueForKey:@"ETag"] forKey:@"eTag"];
                [dict setObject:[objectInfo valueForKey:@"LastModified"] forKey:@"lastModified"];
                [dict setObject:[NSNumber numberWithDouble:[[objectInfo valueForKey:@"Size"] doubleValue]] forKey:@"size"];
                [array addObject:dict];
            }
            NSString *nextMarker = nil;
            if (result.nextMarker == nil) {
                nextMarker = @"";
            }else{
                nextMarker = result.nextMarker;
            }
            [self sendEventWithName:@"getBuckerFiles" body:@{@"isTruncated":[NSNumber numberWithBool:result.isTruncated],
                                                             @"nextMarker":nextMarker,
                                                             @"buckerFiles":array}];
            resolve(@"getBuckerFilesSuccess");
        } else {
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

//取消上传
RCT_REMAP_METHOD(cancleResumableTask,
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    if (mresumableUpload != nil) {
        [mresumableUpload cancel];
    }
}

//异步断点上传
RCT_REMAP_METHOD(resumableUploadWithRecordPathSetting, bucketName:(NSString *)BucketName
                 sourceFile:(NSString *)sourceFile
                 OssFile:(NSString *)OssFile
                 needCallBack:(int)needCallBack
                 callbackUrl:(NSString *)callbackUrl
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject){
    //阿里云视频上传的方法
    __block NSString * recordKey;
    __block NSString * _uploadid;
    NSURL *filePath = [NSURL URLWithString:sourceFile];
    NSString * bucketName = BucketName;
    NSString * objectKey;
    if (_uploadid == nil) {
        objectKey = OssFile;
        _uploadid = objectKey;
    } else{
        objectKey = _uploadid;
    }
    [[[[[[OSSTask taskWithResult:nil] continueWithBlock:^id(OSSTask *task) {
        // 为该文件构造一个唯一的记录键
        //        NSURL * fileURL = [NSURL fileURLWithPath:filePath];
        NSDate * lastModified;
        NSError * error;
        [filePath getResourceValue:&lastModified forKey:NSURLContentModificationDateKey error:&error];
        if (error) {
            return [OSSTask taskWithError:error];
        }
        recordKey = [NSString stringWithFormat:@"%@-%@-%@-%@", bucketName, objectKey, [OSSUtil getRelativePath:[filePath absoluteString]], lastModified];
        NSLog(@"recordKeyrecordKeyrecordKey-------%@",recordKey);
        // 通过记录键查看本地是否保存有未完成的UploadId
        NSUserDefaults * userDefault = [NSUserDefaults standardUserDefaults];

        return [OSSTask taskWithResult:[userDefault objectForKey:recordKey]];
    }]
        continueWithSuccessBlock:^id(OSSTask *task) {
            if (!task.result) {
                // 如果本地尚无记录，调用初始化UploadId接口获取
                OSSInitMultipartUploadRequest * initMultipart = [OSSInitMultipartUploadRequest new];
                initMultipart.bucketName = bucketName;
                initMultipart.objectKey = objectKey;
                initMultipart.contentType = @"application/octet-stream";
                return [client multipartUploadInit:initMultipart];
            }
            OSSLogVerbose(@"An resumable task for uploadid: %@", task.result);
            return task;
        }]
       continueWithSuccessBlock:^id(OSSTask *task) {
           NSString * uploadId = nil;

           if (task.error) {
               return task;
           }
           if ([task.result isKindOfClass:[OSSInitMultipartUploadResult class]]) {
               uploadId = ((OSSInitMultipartUploadResult *)task.result).uploadId;
           } else {
               uploadId = task.result;
           }

           if (!uploadId) {
               return [OSSTask taskWithError:[NSError errorWithDomain:OSSClientErrorDomain
                                                                 code:OSSClientErrorCodeNilUploadid
                                                             userInfo:@{OSSErrorMessageTOKEN: @"Can't get an upload id"}]];
           }
           // 将“记录键：UploadId”持久化到本地存储
           NSUserDefaults * userDefault = [NSUserDefaults standardUserDefaults];
           [userDefault setObject:uploadId forKey:recordKey];
           [userDefault synchronize];
           return [OSSTask taskWithResult:uploadId];
       }]
      continueWithSuccessBlock:^id(OSSTask *task) {
          // 持有UploadId上传文件
          OSSResumableUploadRequest * resumableUpload = [OSSResumableUploadRequest new];
          resumableUpload.bucketName = bucketName;
          resumableUpload.objectKey = objectKey;
          resumableUpload.uploadId = task.result;
          resumableUpload.uploadingFileURL = filePath;
          resumableUpload.uploadProgress = ^(int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
              float number = (float)totalBytesSent/(float)totalBytesExpectedToSend;
              NSLog(@"number = %f",number);
              [self sendEventWithName: @"esumableUploadProgress" body:@{@"currentSize": [NSString stringWithFormat:@"%lld",totalBytesSent],
                                                                        @"totalSize": [NSString stringWithFormat:@"%lld",totalBytesExpectedToSend],
                                                                        @"progressValue": [NSString stringWithFormat:@"%lld",totalBytesSent * 100/totalBytesExpectedToSend]}];
          };
          mresumableUpload = resumableUpload;
          return [client resumableUpload:resumableUpload];
      }]
     continueWithBlock:^id(OSSTask *task) {
         if (task.error) {
             if ([task.error.domain isEqualToString:OSSClientErrorDomain] && task.error.code == OSSClientErrorCodeCannotResumeUpload) {
                 // 如果续传失败且无法恢复，需要删除本地记录的UploadId，然后重启任务
                 [[NSUserDefaults standardUserDefaults] removeObjectForKey:recordKey];
             }
         } else {
             NSFileManager *fm=[NSFileManager defaultManager];
             if ([fm fileExistsAtPath:[filePath absoluteString]]) {
                 [fm removeItemAtPath:[filePath absoluteString] error:nil];
             }
             NSLog(@"上传完成!");
             [self sendEventWithName: @"resumableUploadSuccess" body:nil];
             resolve(@YES);
             // 上传成功，删除本地保存的UploadId
             _uploadid = nil;
             [[NSUserDefaults standardUserDefaults] removeObjectForKey:recordKey];
             //[self uploadVideoInfoWithObjectKey:objectKey duration:[NSString stringWithFormat:@"%f.1",VideoDuration]];
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
    // optional fields
    put.uploadProgress = ^(int64_t bytesSent, int64_t totalByteSent, int64_t totalBytesExpectedToSend) {
        NSLog(@"%lld, %lld, %lld", bytesSent, totalByteSent, totalBytesExpectedToSend);
        [self sendEventWithName: @"uploadProgress" body:@{@"everySentSize":[NSString stringWithFormat:@"%lld",bytesSent],
                                                          @"currentSize": [NSString stringWithFormat:@"%lld",totalByteSent],
                                                          @"totalSize": [NSString stringWithFormat:@"%lld",totalBytesExpectedToSend]}];

    };
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

#pragma mark - 保存文件至沙盒
- (NSString *) saveFile:(NSData *)fileData withName:(NSString *)fileName
{
    NSArray *paths=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory=[paths objectAtIndex:0];
    NSString *fullPathToFile=[documentsDirectory stringByAppendingPathComponent:fileName];
    [fileData writeToFile:fullPathToFile atomically:NO];
    return fullPathToFile;
}

@end
