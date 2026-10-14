#include <QGuiApplication>
#include <QQuickView>
#include <QQmlEngine>
#include <QQuickItem>
#include <QTest>
#include <cstdio>
int main(int argc,char **argv) {
 QGuiApplication app(argc,argv); QQuickView view;
 view.engine()->addImportPath(QString::fromLocal8Bit(argv[1]));
 view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])+"/panel.qml"));
 if(view.status()==QQuickView::Error) { for(const auto &e:view.errors()) fprintf(stderr,"%s\n",qPrintable(e.toString())); return 1; }
 view.show(); QTest::qWait(150);
 auto root=view.rootObject(); auto panel=root->findChild<QQuickItem*>("fullpanel");
 if(!panel) return 2;
 auto host=panel->property("hostWidget").value<QObject*>();
 QQuickItem *scroll=nullptr;
 for(auto item:root->findChildren<QQuickItem*>()) if(item->inherits("QQuickFlickable")) { scroll=item; break; }
 if(!scroll || scroll->height()>720 || scroll->height()<100) return 3;
 panel->setProperty("showAdvanced",true); QTest::qWait(100);
 if(scroll->property("contentHeight").toDouble()<=scroll->height()) return 4;
 scroll->setProperty("contentY",scroll->property("contentHeight").toDouble()-scroll->height());
 QTest::qWait(100);
 if(scroll->property("contentY").toDouble()<=0) return 5;
 panel->setProperty("showAdvanced",false);
 QMetaObject::invokeMethod(host,"selectVisual",Q_ARG(QVariant,QVariant("Strings")));
 QTest::qWait(100); scroll->setProperty("contentY",0);
 view.grabWindow().save(QString::fromLocal8Bit(argv[1])+"/panel.png");
 QMetaObject::invokeMethod(host,"writeVizOption",Q_ARG(QVariant,QVariant("enabled")),Q_ARG(QVariant,QVariant(false)));
 QTest::qWait(100);
 if(scroll->property("contentHeight").toDouble()>scroll->height()+1) return 6;
 puts("PASS: full settings panel bounds tall content, scrolls to advanced options, switches visual, and collapses when disabled");
}
