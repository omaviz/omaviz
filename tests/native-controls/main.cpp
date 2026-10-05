#include <QGuiApplication>
#include <QQuickView>
#include <QQmlEngine>
#include <QQuickItem>
#include <QTest>
#include <QInputMethodEvent>
#include <cstdio>
int main(int argc,char **argv) {
 QGuiApplication app(argc,argv); QQuickView view;
 if(argc!=2) { fprintf(stderr,"Expected fixture path\n"); return 2; }
 view.engine()->addImportPath(QString::fromLocal8Bit(argv[1]));
 view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])+"/scene.qml"));
 if(view.status()==QQuickView::Error) { for(const auto &e:view.errors()) fprintf(stderr,"%s\n",qPrintable(e.toString())); return 2; }
 view.show(); QTest::qWait(100);
 auto root=view.rootObject(); auto chip=root->findChild<QQuickItem*>("chip");
 auto selector=root->findChild<QQuickItem*>("select"); auto hex=root->findChild<QQuickItem*>("hex");
 if(!chip || !selector || !hex) { fprintf(stderr,"Missing control fixture\n"); return 2; }
 QQuickItem *input=nullptr;
 for(auto item:hex->findChildren<QQuickItem*>()) if(item->inherits("QQuickTextInput")) input=item;
 if(!input) { fprintf(stderr,"Missing text input\n"); return 2; }
 int failures=0;
 auto check=[&](bool ok,const char *message) { printf("%s: %s\n",ok?"PASS":"FAIL",message); failures+=!ok; };
 chip->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_Space); QTest::qWait(30);
 check(root->property("clicks").toInt()==1,"Space activates color chip");
 QTest::keyClick(&view,Qt::Key_Return); QTest::qWait(30);
 check(root->property("clicks").toInt()==2,"Enter activates color chip");
 int before=root->property("clicks").toInt();
 QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,chip->mapToScene({30,15}).toPoint());
 check(root->property("clicks").toInt()==before+1,"mouse activates color chip once");
 selector->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_Down); QTest::qWait(30);
 check(selector->property("currentIndex").toInt()==1 && root->property("lastSelection").toInt()==1,"keyboard changes visualization selection");
 auto edit=[&](QString value) {
   input->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_A,Qt::ControlModifier);
   QInputMethodEvent paste; paste.setCommitString(value); QCoreApplication::sendEvent(input,&paste); QTest::qWait(20);
 };
 edit("#12abef"); QTest::keyClick(&view,Qt::Key_Return); QTest::qWait(30);
 check(root->property("accepted").toString()=="#12abef","valid hex commits on Enter");
 edit("#12"); selector->forceActiveFocus(); QTest::qWait(30);
 check(input->property("text").toString()=="#12abef","incomplete hex restores saved color on blur");
 check(root->property("accepted").toString()=="#12abef","incomplete hex does not persist");
 hex->setProperty("value","#abcdef"); QTest::qWait(30);
 check(input->property("text").toString()=="#abcdef","external palette updates hex field after editing");
 chip->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_Tab); QTest::qWait(30);
 check(view.activeFocusItem()!=chip,"Tab advances focus");
 auto link=root->findChild<QQuickItem*>("link"); auto swatch=root->findChild<QQuickItem*>("swatch");
 link->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_Space);
 swatch->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_Return);
 check(root->property("actions").toInt()==2,"keyboard activates links and palette swatches");
 auto slider=root->findChild<QQuickItem*>("slider"); slider->forceActiveFocus();
 QTest::keyClick(&view,Qt::Key_Right);
 check(qAbs(slider->property("value").toDouble()-1.1)<.001,"slider arrow changes one step");
 QTest::keyClick(&view,Qt::Key_Home);
 check(qAbs(slider->property("value").toDouble()-.5)<.001,"slider Home selects minimum");
 QTest::keyClick(&view,Qt::Key_End); QTest::keyClick(&view,Qt::Key_Right);
 check(qAbs(slider->property("value").toDouble()-2)<.001,"slider End and arrow respect maximum");
 QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,slider->mapToScene({1,slider->height()/2}).toPoint());
 check(slider->property("value").toDouble()<.52,"mouse still adjusts shell slider");
 return failures?1:0;
}
