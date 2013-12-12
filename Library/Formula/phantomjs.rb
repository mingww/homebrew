require 'formula'

class Phantomjs < Formula
  homepage 'http://www.phantomjs.org/'
  url 'https://phantomjs.googlecode.com/files/phantomjs-1.9.2-source.zip'
  sha1 '08559acdbbe04e963632bc35e94c1a9a082b6da1'

  def patches
    DATA
  end

  def install
    inreplace 'src/qt/preconfig.sh', '-arch x86', '-arch x86_64' if MacOS.prefer_64_bit?
    args = ['--confirm', '--qt-config']
    # we have to disable these to avoid triggering Qt optimization code
    # that will fail in superenv (in --env=std, Qt seems aware of this)
    args << '-no-3dnow -no-ssse3' if superenv?
    system './build.sh', *args
    bin.install 'bin/phantomjs'
    (share+'phantomjs').install 'examples'
  end
end
__END__
diff --git a/src/qt/src/gui/kernel/qt_cocoa_helpers_mac_p.h b/src/qt/src/gui/kernel/qt_cocoa_helpers_mac_p.h
index c068234..90d2ca0 100644
--- a/src/qt/src/gui/kernel/qt_cocoa_helpers_mac_p.h
+++ b/src/qt/src/gui/kernel/qt_cocoa_helpers_mac_p.h
@@ -110,6 +110,7 @@
 #include "private/qt_mac_p.h"

 struct HIContentBorderMetrics;
+struct TabletProximityRec;

 #ifdef Q_WS_MAC32
 typedef struct _NSPoint NSPoint; // Just redefine here so I don't have to pull in all of Cocoa.
@@ -155,7 +156,6 @@ bool qt_dispatchKeyEvent(void * /*NSEvent * */ keyEvent, QWidget *widgetToGetEve
 void qt_dispatchModifiersChanged(void * /*NSEvent * */flagsChangedEvent, QWidget *widgetToGetEvent);
 bool qt_mac_handleTabletEvent(void * /*QCocoaView * */view, void * /*NSEvent * */event);
 inline QApplication *qAppInstance() { return static_cast<QApplication *>(QCoreApplication::instance()); }
-struct ::TabletProximityRec;
 void qt_dispatchTabletProximityEvent(const ::TabletProximityRec &proxRec);
 Qt::KeyboardModifiers qt_cocoaModifiers2QtModifiers(ulong modifierFlags);
 Qt::KeyboardModifiers qt_cocoaDragOperation2QtModifiers(uint dragOperations);
 diff --git a/src/networkaccessmanager.cpp b/src/networkaccessmanager.cpp
index fbe8af1..b04463b 100644
--- a/src/networkaccessmanager.cpp
+++ b/src/networkaccessmanager.cpp
@@ -59,6 +59,9 @@ static const char *toString(QNetworkAccessManager::Operation op)
     case QNetworkAccessManager::PostOperation:
         str = "POST";
         break;
+    case QNetworkAccessManager::PatchOperation:
+        str = "PATCH";
+        break;
     case QNetworkAccessManager::DeleteOperation:
         str = "DELETE";
         break;
diff --git a/src/qt/src/3rdparty/webkit/Source/WebCore/platform/network/qt/QNetworkReplyHandler.cpp b/src/qt/src/3rdparty/webkit/Source/WebCore/platform/network/qt/QNetworkReplyHandler.cpp
index 3cf6439..0921225 100644
--- a/src/qt/src/3rdparty/webkit/Source/WebCore/platform/network/qt/QNetworkReplyHandler.cpp
+++ b/src/qt/src/3rdparty/webkit/Source/WebCore/platform/network/qt/QNetworkReplyHandler.cpp
@@ -368,6 +368,8 @@ String QNetworkReplyHandler::httpMethod() const
         return "POST";
     case QNetworkAccessManager::PutOperation:
         return "PUT";
+    case QNetworkAccessManager::PatchOperation:
+        return "PATCH";
     case QNetworkAccessManager::DeleteOperation:
         return "DELETE";
     case QNetworkAccessManager::CustomOperation:
@@ -395,6 +397,8 @@ QNetworkReplyHandler::QNetworkReplyHandler(ResourceHandle* handle, LoadType load
         m_method = QNetworkAccessManager::PostOperation;
     else if (r.httpMethod() == "PUT")
         m_method = QNetworkAccessManager::PutOperation;
+    else if (r.httpMethod() == "PATCH")
+        m_method = QNetworkAccessManager::PatchOperation;
     else if (r.httpMethod() == "DELETE")
         m_method = QNetworkAccessManager::DeleteOperation;
     else
@@ -623,7 +627,7 @@ QNetworkReply* QNetworkReplyHandler::sendNetworkRequest(QNetworkAccessManager* m
         && (!url.toLocalFile().isEmpty() || url.scheme() == QLatin1String("data")))
         m_method = QNetworkAccessManager::GetOperation;

-    if (m_method != QNetworkAccessManager::PostOperation && m_method != QNetworkAccessManager::PutOperation) {
+    if (m_method != QNetworkAccessManager::PostOperation && m_method != QNetworkAccessManager::PutOperation && m_method != QNetworkAccessManager::PatchOperation) {
         // clearing Contents-length and Contents-type of the requests that do not have contents.
         m_request.setHeader(QNetworkRequest::ContentTypeHeader, QVariant());
         m_request.setHeader(QNetworkRequest::ContentLengthHeader, QVariant());
@@ -641,6 +645,15 @@ QNetworkReply* QNetworkReplyHandler::sendNetworkRequest(QNetworkAccessManager* m
             postDevice->setParent(result);
             return result;
         }
+        case QNetworkAccessManager::PatchOperation: {
+            FormDataIODevice* patchDevice = new FormDataIODevice(request.httpBody());
+            // We may be uploading files so prevent QNR from buffering data
+            m_request.setHeader(QNetworkRequest::ContentLengthHeader, patchDevice->getFormDataSize());
+            m_request.setAttribute(QNetworkRequest::DoNotBufferUploadDataAttribute, QVariant(true));
+            QNetworkReply* result = manager->patch(m_request, patchDevice);
+            patchDevice->setParent(result);
+            return result;
+        }
         case QNetworkAccessManager::HeadOperation:
             return manager->head(m_request);
         case QNetworkAccessManager::PutOperation: {
diff --git a/src/qt/src/3rdparty/webkit/Source/WebKit/qt/Api/qwebframe.cpp b/src/qt/src/3rdparty/webkit/Source/WebKit/qt/Api/qwebframe.cpp
index 04453b6..c517734 100644
--- a/src/qt/src/3rdparty/webkit/Source/WebKit/qt/Api/qwebframe.cpp
+++ b/src/qt/src/3rdparty/webkit/Source/WebKit/qt/Api/qwebframe.cpp
@@ -908,6 +908,9 @@ void QWebFrame::load(const QNetworkRequest &req,
         case QNetworkAccessManager::PostOperation:
             request.setHTTPMethod("POST");
             break;
+        case QNetworkAccessManager::PatchOperation:
+            request.setHTTPMethod("PATCH");
+            break;
         case QNetworkAccessManager::DeleteOperation:
             request.setHTTPMethod("DELETE");
             break;
diff --git a/src/qt/src/network/access/qhttp.cpp b/src/qt/src/network/access/qhttp.cpp
index dea23f9..984133d 100644
--- a/src/qt/src/network/access/qhttp.cpp
+++ b/src/qt/src/network/access/qhttp.cpp
@@ -2254,6 +2254,27 @@ int QHttp::post(const QString &path, const QByteArray &data, QIODevice *to)
     return d->addRequest(new QHttpPGHRequest(header, new QByteArray(data), to));
 }

+int QHttp::patch(const QString &path, QIODevice *data, QIODevice *to )
+{
+    Q_D(QHttp);
+    QHttpRequestHeader header(QLatin1String("PATCH"), path);
+    header.setValue(QLatin1String("Connection"), QLatin1String("Keep-Alive"));
+    return d->addRequest(new QHttpPGHRequest(header, data, to));
+}
+
+/*!
+    \overload
+
+    \a data is used as the content data of the HTTP request.
+*/
+int QHttp::patch(const QString &path, const QByteArray &data, QIODevice *to)
+{
+    Q_D(QHttp);
+    QHttpRequestHeader header(QLatin1String("PATCH"), path);
+    header.setValue(QLatin1String("Connection"), QLatin1String("Keep-Alive"));
+    return d->addRequest(new QHttpPGHRequest(header, new QByteArray(data), to));
+}
+
 /*!
     Sends a header request for \a path to the server set by setHost()
     or as specified in the constructor.
*/
diff --git a/src/qt/src/network/access/qhttp.h b/src/qt/src/network/access/qhttp.h
index 9700e6e..1590806 100644
--- src/qt/src/network/access/qhttp.h
+++ src/qt/src/network/access/qhttp.h
@@ -223,6 +223,8 @@ public:
     int get(const QString &path, QIODevice *to=0);
     int post(const QString &path, QIODevice *data, QIODevice *to=0 );
     int post(const QString &path, const QByteArray &data, QIODevice *to=0);
+    int patch(const QString &path, QIODevice *data, QIODevice *to=0 );
+    int patch(const QString &path, const QByteArray &data, QIODevice *to=0);
     int head(const QString &path);
     int request(const QHttpRequestHeader &header, QIODevice *device=0, QIODevice *to=0);
     int request(const QHttpRequestHeader &header, const QByteArray &data, QIODevice *to=0);
diff --git a/src/qt/src/network/access/qhttpnetworkrequest.cpp b/src/qt/src/network/access/qhttpnetworkrequest.cpp
index 617541f..78a2d82 100644
--- a/src/qt/src/network/access/qhttpnetworkrequest.cpp
+++ b/src/qt/src/network/access/qhttpnetworkrequest.cpp
@@ -90,6 +90,9 @@ QByteArray QHttpNetworkRequestPrivate::methodName() const
     case QHttpNetworkRequest::Post:
         return "POST";
         break;
+    case QHttpNetworkRequest::Patch:
+        return "PATCH";
+        break;
     case QHttpNetworkRequest::Options:
         return "OPTIONS";
         break;
diff --git a/src/qt/src/network/access/qhttpnetworkrequest_p.h b/src/qt/src/network/access/qhttpnetworkrequest_p.h
index 3b98342..4b6d654 100644
--- a/src/qt/src/network/access/qhttpnetworkrequest_p.h
+++ b/src/qt/src/network/access/qhttpnetworkrequest_p.h
@@ -69,6 +69,7 @@ public:
         Get,
         Head,
         Post,
+        Patch,
         Put,
         Delete,
         Trace,
diff --git a/src/qt/src/network/access/qnetworkaccesshttpbackend.cpp b/src/qt/src/network/access/qnetworkaccesshttpbackend.cpp
index 1d048ee..ffd6b32 100644
--- a/src/qt/src/network/access/qnetworkaccesshttpbackend.cpp
+++ b/src/qt/src/network/access/qnetworkaccesshttpbackend.cpp
@@ -171,6 +171,7 @@ QNetworkAccessHttpBackendFactory::create(QNetworkAccessManager::Operation op,
     switch (op) {
     case QNetworkAccessManager::GetOperation:
     case QNetworkAccessManager::PostOperation:
+    case QNetworkAccessManager::PatchOperation:
     case QNetworkAccessManager::HeadOperation:
     case QNetworkAccessManager::PutOperation:
     case QNetworkAccessManager::DeleteOperation:
@@ -453,6 +454,12 @@ void QNetworkAccessHttpBackend::postRequest()
         createUploadByteDevice();
         break;

+    case QNetworkAccessManager::PatchOperation:
+        invalidateCache();
+        httpRequest.setOperation(QHttpNetworkRequest::Patch);
+        createUploadByteDevice();
+        break;
+
     case QNetworkAccessManager::PutOperation:
         invalidateCache();
         httpRequest.setOperation(QHttpNetworkRequest::Put);
diff --git a/src/qt/src/network/access/qnetworkaccessmanager.cpp b/src/qt/src/network/access/qnetworkaccessmanager.cpp
index 84b1b4b..6cc63d2 100644
--- a/src/qt/src/network/access/qnetworkaccessmanager.cpp
+++ b/src/qt/src/network/access/qnetworkaccessmanager.cpp
@@ -715,6 +715,56 @@ QNetworkReply *QNetworkAccessManager::put(const QNetworkRequest &request, const
     return reply;
 }

+QNetworkReply *QNetworkAccessManager::patch(const QNetworkRequest &request, QHttpMultiPart *multiPart)
+{
+    QNetworkRequest newRequest = d_func()->prepareMultipart(request, multiPart);
+    QIODevice *device = multiPart->d_func()->device;
+    QNetworkReply *reply = patch(newRequest, device);
+    return reply;
+}
+
+/*!
+ Uploads the contents of \a data to the destination \a request and
+ returnes a new QNetworkReply object that will be open for reply.
+
+ \a data must be opened for reading when this function is called
+ and must remain valid until the finished() signal is emitted for
+ this reply.
+
+ Whether anything will be available for reading from the returned
+ object is protocol dependent. For HTTP, the server may send a
+ small HTML page indicating the upload was successful (or not).
+ Other protocols will probably have content in their replies.
+
+ \note For HTTP, this request will send a PUT request, which most servers
+ do not allow. Form upload mechanisms, including that of uploading
+ files through HTML forms, use the POST mechanism.
+
+ \sa get(), post(), deleteResource(), sendCustomRequest()
+ /
+QNetworkReply *QNetworkAccessManager::patch(const QNetworkRequest &request, QIODevice *data)
+{
+    return d_func()->postProcess(createRequest(QNetworkAccessManager::PatchOperation, request, data));
+}
+
+/*!
+ \overload
+
+ Sends the contents of the \a data byte array to the destination
+ specified by \a request.
+ */
+QNetworkReply *QNetworkAccessManager::patch(const QNetworkRequest &request, const QByteArray &data)
+{
+    QBuffer *buffer = new QBuffer;
+    buffer->setData(data);
+    buffer->open(QIODevice::ReadOnly);
+
+    QNetworkReply *reply = patch(request, buffer);
+    buffer->setParent(reply);
+    return reply;
+}
+
+
 /*!
     \since 4.6
*/
diff --git a/src/qt/src/network/access/qnetworkaccessmanager.h b/src/qt/src/network/access/qnetworkaccessmanager.h
index 26a28e1..52b8452 100644
--- a/src/qt/src/network/access/qnetworkaccessmanager.h
+++ b/src/qt/src/network/access/qnetworkaccessmanager.h
@@ -84,6 +84,7 @@ public:
         PutOperation,
         PostOperation,
         DeleteOperation,
+        PatchOperation,
         CustomOperation,

         UnknownOperation = 0
@@ -121,6 +122,9 @@ public:
     QNetworkReply *put(const QNetworkRequest &request, QIODevice *data);
     QNetworkReply *put(const QNetworkRequest &request, const QByteArray &data);
     QNetworkReply *put(const QNetworkRequest &request, QHttpMultiPart *multiPart);
+    QNetworkReply *patch(const QNetworkRequest &request, QIODevice *data);
+    QNetworkReply *patch(const QNetworkRequest &request, const QByteArray &data);
+    QNetworkReply *patch(const QNetworkRequest &request, QHttpMultiPart *multiPart);
     QNetworkReply *deleteResource(const QNetworkRequest &request);
     QNetworkReply *sendCustomRequest(const QNetworkRequest &request, const QByteArray &verb, QIODevice *data = 0);

diff --git a/src/webpage.cpp b/src/webpage.cpp
index c76a4b8..a56b46a 100644
--- a/src/webpage.cpp
+++ b/src/webpage.cpp
@@ -817,6 +817,8 @@ void WebPage::openUrl(const QString &address, const QVariant &op, const QVariant
         networkOp = QNetworkAccessManager::PutOperation;
     else if (operation == "post")
         networkOp = QNetworkAccessManager::PostOperation;
+    else if (operation == "patch")
+        networkOp = QNetworkAccessManager::PatchOperation;
     else if (operation == "delete")
         networkOp = QNetworkAccessManager::DeleteOperation;
