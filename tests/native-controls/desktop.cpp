#include <QGuiApplication>
#include <QQuickView>
#include <QQuickItem>
#include <QTest>
#include <cstdio>
#include <cmath>
int main(int argc,char **argv) {
 QGuiApplication app(argc,argv); QQuickView view; view.setResizeMode(QQuickView::SizeRootObjectToView);
 view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])+"/desktop.qml"));
 if(view.status()==QQuickView::Error) return 1;
 view.show(); QTest::qWait(100);
 auto root=view.rootObject(); auto tray=root->findChild<QQuickItem*>("tray"); auto playback=root->findChild<QQuickItem*>("playback");
 if(!tray || !playback) return 2;
 QTest::mouseMove(&view,{250,150}); QTest::qWait(250);
 QPoint position=playback->mapToScene(QPointF(18,18)).toPoint();
 QTest::mouseMove(&view,position); QTest::qWait(900);
 if(!tray->property("shown").toBool() || tray->opacity()<.99) return 3;
 QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,position); QTest::qWait(450);
 if(!playback->isVisible() || playback->property("label").toString()!=QString::fromUtf8("▶")) return 4;
 if(!tray->property("shown").toBool()) return 5;
 QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,position); QTest::qWait(450);
 if(playback->property("accessibleLabel").toString()!="Pause") return 6;
 puts("PASS: hover remains stable over controls; pause exposes Play; Play resumes");
 view.resize(320,160); QTest::qWait(100);
 auto close=root->findChild<QQuickItem*>("close");
 const auto bounds=close->mapRectToScene(close->boundingRect());
 if(bounds.right()>view.width() || bounds.bottom()>view.height()) return 7;
 puts("PASS: desktop actions fit at minimum size");
 QTest::mouseMove(&view,{-20,-20}); tray->setProperty("shown",false); QTest::qWait(250);
 view.requestActivate(); QTest::qWait(50); QTest::keyClick(&view,Qt::Key_Tab); QTest::qWait(250);
 if(!tray->property("shown").toBool() || !playback->hasActiveFocus()) { fprintf(stderr,"keyboard tray=%d focus=%d activeWindow=%d\n",tray->property("shown").toBool(),playback->hasActiveFocus(),view.isActive()); return 8; }
 QTest::keyClick(&view,Qt::Key_Space); QTest::qWait(100);
 if(playback->property("accessibleLabel").toString()!="Play") return 9;
 QTest::qWait(450);
 if(!tray->property("shown").toBool()) return 10;
 puts("PASS: Tab reveals desktop actions and keyboard playback keeps them visible");
 auto player=root->property("activePlayer").value<QObject*>();
 auto other=root->property("secondPlayer").value<QObject*>();
 other->setProperty("isPlaying",true); QTest::qWait(30);
 if(root->property("activePlayer").value<QObject*>()!=player || tray->property("player").value<QObject*>()!=player) return 20;
 auto previous=root->findChild<QQuickItem*>("previous"); auto next=root->findChild<QQuickItem*>("next");
 previous->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_Return);
 next->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_Space);
 if(player->property("previousCount").toInt()!=1 || player->property("nextCount").toInt()!=1) return 21;
 player->setProperty("canGoPrevious",false); player->setProperty("canGoNext",false); QTest::qWait(30);
 if(previous->isVisible() || next->isVisible()) return 22;
 player->setProperty("canPause",false); player->setProperty("canPlay",false); player->setProperty("canTogglePlaying",false); QTest::qWait(30);
 if(playback->isVisible()) return 23;
 puts("PASS: media stays on one player; previous/next execute and unsupported actions disappear");
 player->setProperty("canGoPrevious",true); player->setProperty("canGoNext",true); player->setProperty("canPlay",true);
 view.resize(600,200); QTest::qWait(100);
 view.grabWindow().save(QString::fromLocal8Bit(argv[1])+"/transport.png");
 view.resize(320,160); QTest::qWait(100);
 view.grabWindow().save(QString::fromLocal8Bit(argv[1])+"/transport-small.png");
 close->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_Return); QTest::qWait(30);
 if(!root->property("closed").toBool()) return 11;
 puts("PASS: keyboard closes desktop through the same action");
 auto viewport=root->findChild<QQuickItem*>("viewport");
 auto artwork=root->findChild<QQuickItem*>("artworkBackdrop");
 if(!viewport || !artwork) return 12;
 for(const auto &mode: {"Waves","Strings","Siri","Bars","Orbit","PixelWave","Bokeh"}) {
  root->setProperty("vizConfig",QVariantMap{{"visual",mode},{"enabled",true}});
  for(const auto &size: {QSize(600,200),QSize(1200,180),QSize(360,600),QSize(320,160)}) {
   view.resize(size); QTest::qWait(25);
   if(viewport->x()<0 || viewport->y()<0 || viewport->x()+viewport->width()>view.width() || viewport->y()+viewport->height()>view.height()) return 13;
   const bool fitted=QString(mode)=="Waves" || QString(mode)=="Siri";
   if(fitted && std::abs(viewport->width()/viewport->height()-3)>0.001) return 14;
   if(!fitted &&
      (std::abs(viewport->width()-(view.width()-8))>0.001 ||
       std::abs(viewport->height()-(view.height()-8))>0.001)) return 15;
   if(artwork->property("active").toBool() != (QString(mode)=="Bars" || QString(mode)=="Orbit" || QString(mode)=="PixelWave" || QString(mode)=="Bokeh")) return 16;
  }
 }
 puts("PASS: Siri/Waves preserve 3:1 and Strings/Bars/particle/radial modes fill the desktop at normal, wide, tall, and minimum sizes");
 root->setProperty("vizConfig",QVariantMap{{"visual","Bars"},{"enabled",true}});
 view.resize(600,200); QTest::qWait(50);
 const double smallSlot=viewport->width()/viewport->property("spectrumBarCount").toInt();
 view.resize(1200,400); QTest::qWait(50);
 const double wideSlot=viewport->width()/viewport->property("spectrumBarCount").toInt();
 if(smallSlot<9 || smallSlot>11 || wideSlot<smallSlot*1.5 || wideSlot>smallSlot*2.0) return 19;
 puts("PASS: spectrum bars grow 50-100% wider in a wide desktop");
 root->setProperty("vizConfig",QVariantMap{{"visual","Bars"},{"artwork",true},{"enabled",true}});
 QTest::qWait(100);
 if(!artwork->property("active").toBool() || artwork->property("item").value<QObject*>()==nullptr) return 17;
 root->setProperty("vizConfig",QVariantMap{{"visual","Strings"},{"artwork",true},{"enabled",true}});
 QTest::qWait(100);
 if(artwork->property("active").toBool() || artwork->property("item").value<QObject*>()!=nullptr) return 18;
 puts("PASS: leaving artwork spectrum unloads the cached backdrop");
 for(const auto &mode: {"Orbit","PixelWave","Bokeh"}) {
  root->setProperty("vizConfig",QVariantMap{{"visual",mode},{"artwork",true},{"enabled",true}}); QTest::qWait(50);
  if(!artwork->property("active").toBool() || artwork->property("item").value<QObject*>()==nullptr) return 21;
  root->setProperty("vizConfig",QVariantMap{{"visual",mode},{"artwork",false},{"enabled",true}}); QTest::qWait(50);
  if(artwork->property("active").toBool() || artwork->property("item").value<QObject*>()!=nullptr) return 22;
 }
 puts("PASS: particle/radial artwork backdrops load and fully unload on demand");
}
