/**
 * @flow
 */
'use strict';

import {
  NativeModules,
  NativeAppEventEmitter,
  NativeEventEmitter,
  Platform
} from 'react-native';
const NativeAliyunOSS = NativeModules.AliyunOSS;
const UPLOAD_EVENT = 'uploadProgress';
const DOWNLOAD_EVENT = 'downloadProgress';
const ESUMA_UPLOAD_EVENT = 'esumableUploadProgress';
const RESUMA_UPLOAD_SUCCESS_EVENT = 'resumableUploadSuccess';
const RESUMA_UPLOAD_FAIL_EVENT = 'resumableUploadFail';

const _subscriptions = new Map();

const AliyunOSS = {
  //开启oss log
  enableOSSLog() {
    NativeAliyunOSS.enableOSSLog();
  },
  /*初始化ossclient，
  **通过AccessKey和SecretKey
  *
  */
  initWithKey(conf, EndPoint) {
    NativeAliyunOSS.initWithKey(conf.AccessKey, conf.SecretKey, conf.SecretToken, EndPoint);
  },
  /*初始化ossclient，
  **通过签名字符串，此处采用的是服务端签名
  *
  */
  initWithSigner(AccessKey, Signature, EndPoint) {
    NativeAliyunOSS.initWithSigner(AccessKey, Signature, EndPoint);
  },
  /*异步上传文件
  **bucketName
  *sourceFile:源文件路径，例如:/User/xx/xx/test.jpg
  *ossFile:目标路径，例如:文件夹/文件名  test/test.jpg
  *updateDate:需要和签名中用到的时间一致
  */
  uploadObjectAsync(conf) {
    return NativeAliyunOSS.uploadObjectAsync(
      conf.bucketName,
      conf.sourceFile,
      conf.ossFile);
  },

  downloadObjectAsync(conf) {
    return NativeAliyunOSS.downloadObjectAsync(
      conf.bucketName,
      conf.ossFile,);
  },

  resumableUploadWithRecordPathSetting(conf,needCallBack,callbackUrl) {
    NativeAliyunOSS.resumableUploadWithRecordPathSetting(
      conf.bucketName,
      conf.sourceFile,
      conf.ossFile,
      needCallBack,
      callbackUrl);
  },

  cancleResumableTask() {
     NativeAliyunOSS.cancleResumableTask();
  },

  deleteFile(bucketName,ossFile) {
    return NativeAliyunOSS.deleteFile(
      bucketName,
      ossFile);
  },

  /*监听上传和下载事件，
  **返回对象3个属性
  *everySentSize:每次上传／下载字节
  *currentSize:当前所需上传／下载字节
  *totalSize:总字节
  */
  addEventListener(type, handler) {
    var listener;
    if (Platform.OS === 'ios') {
      const Emitter = new NativeEventEmitter(NativeAliyunOSS);
      if (type === UPLOAD_EVENT) {
        listener = Emitter.addListener(
          'uploadProgress',
          (uploadData) => {
            handler(uploadData);
          }
        );
      } else if (type === DOWNLOAD_EVENT) {
        listener = Emitter.addListener(
          'downloadProgress',
          (downloadData) => {
            handler(downloadData);
          }
        );
      } else if (type === ESUMA_UPLOAD_EVENT) {
        listener = Emitter.addListener(
          'esumableUploadProgress',
          (esumableData) => {
            handler(esumableData);
          }
        );
      } else if (type === RESUMA_UPLOAD_SUCCESS_EVENT) {
        listener = Emitter.addListener(
          RESUMA_UPLOAD_SUCCESS_EVENT,
          resumableData => {
            handler(resumableData);
          }
        );
      } else if (type === RESUMA_UPLOAD_FAIL_EVENT) {
        listener = Emitter.addListener(
          RESUMA_UPLOAD_FAIL_EVENT,
          resumableData => {
            handler(resumableData);
          }
        );
      } else {
        return false;
      }
    }
    else {
      if (type === UPLOAD_EVENT) {
        listener = NativeAppEventEmitter.addListener(
          'uploadProgress',
          (uploadData) => {
            handler(uploadData);
          }
        );
      } else if (type === DOWNLOAD_EVENT) {
        listener = NativeAppEventEmitter.addListener(
          'downloadProgress',
          (downloadData) => {
            handler(downloadData);
          }
        );
      } else if (type === ESUMA_UPLOAD_EVENT) {
        listener = NativeAppEventEmitter.addListener(
          'esumableUploadProgress',
          (esumableData) => {
            handler(esumableData);
          }
        );
      } else if (type === RESUMA_UPLOAD_SUCCESS_EVENT) {
        listener = NativeAppEventEmitter.addListener(
          RESUMA_UPLOAD_SUCCESS_EVENT,
          resumableData => {
            handler(resumableData);
          }
        );
      } else if (type === RESUMA_UPLOAD_FAIL_EVENT) {
        listener = NativeAppEventEmitter.addListener(
          RESUMA_UPLOAD_FAIL_EVENT,
          resumableData => {
            handler(resumableData);
          }
        );
      } else {
        return false;
      }
    }
    _subscriptions.set(handler, listener);
  },

  removeEventListener(type, handler) {
    if (type !== UPLOAD_EVENT && type !== DOWNLOAD_EVENT && type !== ESUMA_UPLOAD_EVENT
        && type !== RESUMA_UPLOAD_SUCCESS_EVENT && type !== RESUMA_UPLOAD_FAIL_EVENT) {
      return false;
    }
    var listener = _subscriptions.get(handler);
    if (!listener) {
      return;
    }
    listener.remove();
    _subscriptions.delete(handler);
  },

  getBuckerFiles(bucketName,file,maxkeys,marker) {
     return NativeAliyunOSS.getBuckerFiles(bucketName,file,maxkeys,marker);
  },

  addGetBuckerFilesListener(handler) {
    var listener;
    if (Platform.OS === 'ios') {
      const Emitter = new NativeEventEmitter(NativeAliyunOSS);
      listener = Emitter.addListener(
        'getBuckerFiles',
        (buckerFiles) => {
          Emitter.removeAllListeners('getBuckerFiles');
          handler(buckerFiles);
        }
      );
    } else {
      listener = NativeAppEventEmitter.once(
        'getBuckerFiles',
        (buckerFiles) => {
          handler(buckerFiles);
        }
      );
    }
    _subscriptions.set(handler, listener);
  },

  presignConstrainedObjectURLs(bucketName,objectKeys) {
    return NativeAliyunOSS.presignConstrainedObjectURLs(bucketName,objectKeys);
  },

  checkObjectExist(bucketName, objectKey) {
    return new Promise((resolve, reject) => {
      if (Platform.OS === 'ios') {
        const Emitter = new NativeEventEmitter(NativeAliyunOSS);
        Emitter.addListener('checkObjectExist', resp => {
          Emitter.removeAllListeners('checkObjectExist');
          resolve(resp);
        });
      } else {
        NativeAppEventEmitter.once('checkObjectExist', resp => {
          resolve(resp);
        });
      }

      try {
        NativeAliyunOSS.checkObjectExist(bucketName, objectKey);
      } catch (e) {
        reject(e);
        return;
      }
    });
  },

  addPresignConstrainedObjectURLsListener(handler) {
    var listener;
    if (Platform.OS === 'ios') {
      const Emitter = new NativeEventEmitter(NativeAliyunOSS);
      listener = Emitter.addListener(
        'presignConstrainedObjectURLs',
        (objectURLs) => {
          Emitter.removeAllListeners('presignConstrainedObjectURLs');
          handler(objectURLs);
        }
      );
    } else {
      listener = NativeAppEventEmitter.once(
        'presignConstrainedObjectURLs',
        (objectURLs) => {
          handler(objectURLs);
        }
      );
    }
    _subscriptions.set(handler, listener);
  },

};
module.exports = AliyunOSS;
