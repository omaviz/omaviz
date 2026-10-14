#include <QGuiApplication>
#include <QQuickView>
#include <QQmlEngine>
#include <QQuickItem>
#include <QTest>
#include <QInputMethodEvent>
#include <QClipboard>
#include <cstdio>
QQuickItem *findVisual(QQuickItem *root,const QString &name) {
 if(root->objectName()==name) return root;
 for(auto child:root->childItems()) if(auto found=findVisual(child,name)) return found;
 return nullptr;
}
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
 QQuickItem *input=hex->findChild<QQuickItem*>("hex-key-entry");
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
   for (const auto c:value) QTest::keyClick(&view,c.toLatin1()); QTest::qWait(20);
 };
 bool clipboardInputs=false;
 for(auto item:root->findChildren<QQuickItem*>()) clipboardInputs |= item->inherits("QQuickTextInput") || item->inherits("QQuickTextEdit");
 check(!clipboardInputs,"color controls instantiate no clipboard-reading Qt text inputs");
 input->forceActiveFocus();
 const auto beforeClipboard=input->property("text").toString();
 app.clipboard()->setText(QString(1024*1024,'a')); QTest::qWait(30);
 QTest::keyClick(&view,Qt::Key_V,Qt::ControlModifier);
 QInputMethodEvent paste; paste.setCommitString(QString(1024*1024,'b')); QCoreApplication::sendEvent(input,&paste);
 check(input->property("text").toString()==beforeClipboard,"clipboard changes, paste and IME payloads do not enter color controls");
 edit("#12abef"); QTest::keyClick(&view,Qt::Key_Return); QTest::qWait(30);
 check(root->property("accepted").toString()=="#12abef","valid hex commits on Enter");
 edit("#12"); selector->forceActiveFocus(); QTest::qWait(30);
 check(input->property("text").toString()=="#12abef","incomplete hex restores saved color on blur");
 check(root->property("accepted").toString()=="#12abef","incomplete hex does not persist");
 check(!hex->property("validationError").toString().isEmpty(),"invalid hex leaves visible feedback after blur");
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
 auto choices=root->findChild<QQuickItem*>("choices");
 auto option=findVisual(root,"choice-c");
 auto dropdown=root->findChild<QQuickItem*>("choices-dropdown");
 if(!choices || !option || !dropdown) { fprintf(stderr,"choices=%p option=%p dropdown=%p\n",choices,option,dropdown); return 3; }
 check(option->isVisible() && !dropdown->isVisible(),"four choices use directly selectable options");
 option->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_Space); QTest::qWait(30);
 check(choices->property("selected").toString()=="c","direct option selection updates the selected value");
 QVariantList five;
 for(const auto &id:{"a","b","c","d","e"}) five.append(QVariantMap{{"id",id},{"label",id}});
 choices->setProperty("options",five); QTest::qWait(30);
 check(dropdown->isVisible() && dropdown->property("currentIndex").toInt()==2,"five choices use a dropdown and preserve selection");
 dropdown->forceActiveFocus(); QTest::keyClick(&view,Qt::Key_Down); QTest::qWait(30);
 check(choices->property("selected").toString()=="d","dropdown keyboard selection updates the selected value");
 view.grabWindow().save(QString::fromLocal8Bit(argv[1])+"/choices.png");
 return failures?1:0;
}
