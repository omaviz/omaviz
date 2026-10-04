#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <QTimer>
#include <QElapsedTimer>
#include <QImage>
#include <QQuickGraphicsConfiguration>
#include <rhi/qrhi.h>
#include <QDebug>
#include <QProcess>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QQuickItem>
#include <cstdio>
#include <algorithm>
#include <vector>
#include <sys/resource.h>
int main(int argc,char **argv) {
    qInstallMessageHandler([](QtMsgType,const QMessageLogContext &,const QString &s){ fprintf(stderr,"%s\n",qPrintable(s)); });
    QGuiApplication app(argc,argv);
    if(argc<3) { qCritical()<<"usage: probe scene.qml output.png [seconds]"; return 2; }
    QQuickView view;
    view.setFlags(Qt::Tool | Qt::FramelessWindowHint);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    QQuickGraphicsConfiguration graphics;
    graphics.setTimestamps(qEnvironmentVariable("OMAVIZ_PROBE_TIMESTAMPS") != "0");
    view.setGraphicsConfiguration(graphics);
    view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if(view.status()==QQuickView::Error) { for(const auto &e:view.errors()) fprintf(stderr,"%s\n",qPrintable(e.toString())); return 3; }
    QProcess engine;
    QByteArray pending;
    if(qEnvironmentVariableIsSet("OMAVIZ_PROBE_ENGINE")) {
        QObject::connect(&engine,&QProcess::readyReadStandardOutput,&app,[&] {
            pending+=engine.readAllStandardOutput();
            while(pending.contains('\n')) {
                int end=pending.indexOf('\n');
                auto obj=QJsonDocument::fromJson(pending.left(end)).object();
                pending.remove(0,end+1);
                if(obj.contains("bands")) {
                    view.rootObject()->setProperty("inputBands",obj["bands"].toArray().toVariantList());
                    view.rootObject()->setProperty("inputSilent",obj["silent"].toBool());
                }
                if(obj.contains("wave")) view.rootObject()->setProperty("inputWave",obj["wave"].toArray().toVariantList());
            }
        });
        QStringList args {"--source",qEnvironmentVariable("OMAVIZ_PROBE_SOURCE","gen=mixed"),
                          "--bands",qEnvironmentVariable("OMAVIZ_PROBE_BANDS","128")};
        if(qEnvironmentVariable("OMAVIZ_PROBE_WAVE")!="0") args<<"--wave";
        engine.start(qEnvironmentVariable("OMAVIZ_PROBE_ENGINE"),args);
        if(!engine.waitForStarted()) return 5;
    }
    QElapsedTimer clock; clock.start();
    std::vector<double> frames, gpuTimes;
    double warmCpu=0, warmTime=0;
    QTimer::singleShot(1000,&app,[&] {
        rusage r{}; getrusage(RUSAGE_SELF,&r);
        warmCpu=r.ru_utime.tv_sec+r.ru_utime.tv_usec/1e6+r.ru_stime.tv_sec+r.ru_stime.tv_usec/1e6;
        warmTime=clock.elapsed()/1000.;
    });
    QObject::connect(&view,&QQuickWindow::afterFrameEnd,&view,[&] {
        if(qEnvironmentVariable("OMAVIZ_PROBE_TIMESTAMPS")=="0") return;
        auto *swap=view.swapChain();
        double ms=swap?swap->currentFrameCommandBuffer()->lastCompletedGpuTime()*1000:0;
        if(ms>0) QMetaObject::invokeMethod(&app,[&,ms] { if(clock.elapsed()>1000) gpuTimes.push_back(ms); },Qt::QueuedConnection);
    },Qt::DirectConnection);
    double last=0;
    QObject::connect(&view,&QQuickWindow::frameSwapped,&app,[&] {
        double now=clock.nsecsElapsed()/1e6;
        if(last>1000) frames.push_back(now-last);
        last=now;
    });
    view.show();
    if(argc>5) view.resize(atoi(argv[4]),atoi(argv[5]));
    if(qEnvironmentVariableIsSet("OMAVIZ_PROBE_SEQUENCE")) {
        const QString base=QString::fromLocal8Bit(argv[2]);
        for(int i=0;i<3;++i) QTimer::singleShot(2000+i*250,&app,[&,i,base] {
            QString path=base;
            path.replace(".png",QString("-%1.png").arg(i+1));
            view.grabWindow().save(path);
        });
    }
    const int duration=argc>3?std::max(2,atoi(argv[3])):5;
    QTimer::singleShot(duration*1000,&app,[&] {
        const auto image=view.grabWindow();
        if(image.isNull() || !image.save(QString::fromLocal8Bit(argv[2]))) { app.exit(4); return; }
        engine.terminate(); engine.waitForFinished(1000);
        rusage child{}; getrusage(RUSAGE_CHILDREN,&child);
        const double childCpu=child.ru_utime.tv_sec+child.ru_utime.tv_usec/1e6+child.ru_stime.tv_sec+child.ru_stime.tv_usec/1e6;
        qInfo()<<"engine_cpu_pct"<<childCpu/(clock.elapsed()/1000.)*100;
        std::sort(frames.begin(),frames.end());
        rusage usage{}; getrusage(RUSAGE_SELF,&usage);
        double cpu=usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1e6+usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1e6;
        std::sort(gpuTimes.begin(),gpuTimes.end());
        qInfo()<<"gpu_p95_ms"<<(gpuTimes.empty()?-1:gpuTimes[gpuTimes.size()*95/100])
               <<"steady_cpu_pct"<<(cpu-warmCpu)/(clock.elapsed()/1000.-warmTime)*100;
        qInfo()<<"frames"<<frames.size()<<"p50_ms"<<(frames.empty()?0:frames[frames.size()/2])
               <<"p95_ms"<<(frames.empty()?0:frames[frames.size()*95/100])
               <<"cpu_pct_including_startup"<<cpu/(clock.elapsed()/1000.)*100
               <<"graphics_api"<<view.rendererInterface()->graphicsApi();
        app.quit();
    });
    return app.exec();
}
