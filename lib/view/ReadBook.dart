import 'dart:convert';

import 'package:PureBook/common/ReaderPageAgent.dart';
import 'package:PureBook/common/common.dart';
import 'package:PureBook/common/toast.dart';
import 'package:PureBook/common/util.dart';
import 'package:PureBook/entity/BookInfo.dart';
import 'package:PureBook/entity/BookTag.dart';
import 'package:PureBook/entity/Chapter.dart';
import 'package:PureBook/entity/ChapterList.dart';
import 'package:PureBook/event/event.dart';
import 'package:PureBook/model/ThemeModel.dart';
import 'package:PureBook/store/Store.dart';
import 'package:PureBook/view/MyBottomSheet.dart';
import 'package:PureBook/view/MyViewPage.dart';
import 'package:dio/dio.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';

import '../common/Screen.dart';

class ReadBook extends StatefulWidget {
  BookInfo _bookInfo;

  ReadBook(this._bookInfo);

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return new _ReadBookState(_bookInfo);
  }
}

class _ReadBookState extends State<ReadBook> with WidgetsBindingObserver {
  BookInfo _bookInfo;
  BookTag _bookTag;
  static GlobalKey<ScaffoldState> _globalKey = new GlobalKey();
  String content = '';
  double contentH;
  double contentW;
  double fontSize = 25.0;
  MyPageController _pageController;

  _ReadBookState(this._bookInfo);

  bool fix = true;
  List<Chapter> chapters = [];
  var value;

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    SpUtil.putString(_bookInfo.Id.toString(), jsonEncode(_bookTag));
    SpUtil.putDouble('fontSize', fontSize);
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    SpUtil.putString(_bookInfo.Id.toString(), jsonEncode(_bookTag));
    SpUtil.putDouble('fontSize', fontSize);
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    eventBus
        .on<ChapterEvent>()
        .listen((ChapterEvent data) => freshUi(data.chapterId));
    eventBus.on<PageEvent>().listen((PageEvent data) => _changePage(data.page));
    getBookRecord();
    if (SpUtil.haveKey('fontSize')) {
      fontSize = SpUtil.getDouble('fontSize');
    }
    var widgetsBinding = WidgetsBinding.instance;
    widgetsBinding.addPostFrameCallback((callback) {
      asyncInit();
      value = _bookTag.cur.toDouble();
      contentH = ScreenUtil.getScreenH(context) -
          ScreenUtil.getStatusBarH(context) -
          30 -
          60;
      contentW = ScreenUtil.getScreenW(context) - 20;
    });
  }

  asyncInit() async {
    await getChapters();
    if (_bookTag.content == null) {
      await loadChapter(1);
    }
  }

  freshUi(int cur) {
    if (mounted) {
      setState(() {
        value = cur.toDouble();
        _bookTag.cur = cur;
        _bookTag.index = 0;
        loadChapter(1);
      });
    }
  }

//获取本书记录
  getBookRecord() async {
    if (SpUtil.haveKey(_bookInfo.Id.toString())) {
      _bookTag = BookTag.fromJson(
          jsonDecode(SpUtil.getString(_bookInfo.Id.toString())));
      chapters = _bookTag.chapters;
      //slider value
      value = _bookTag.cur.toDouble();
      if (_bookTag.index > _bookTag.pageOffsets.length) {
        _bookTag.index = _bookTag.pageOffsets.length;
      }
      _pageController = MyPageController(initialPage: _bookTag.index);
      //本书已读过
      setState(() {});
    } else {
      _bookTag = new BookTag(0, 0, chapters, _bookInfo.Name);
      _pageController = MyPageController(initialPage: 0);
    }
  }

  getChapters() async {
    var url = Common.chaptersUrl + _bookInfo.Id.toString() + '/';
    var _context = null;
    if (!SpUtil.haveKey(_bookInfo.Id.toString())) {
      _context = context;
    }
    Response response = await Util(_context).http().get(url);

    String data = response.data;
    String replace = data.replaceAll('},]', '}]');
    var jsonDecode3 = jsonDecode(replace)['data'];
    List jsonDecode2 = jsonDecode3['list'];
    List<Chapter> temp = [];
    var list = jsonDecode2.map((m) => new ChapterList.fromJson(m)).toList();
    //第一次加载章节
    for (var i = 0; i < list.length; i++) {
      //目录名hasContent=0
      temp.add(new Chapter(0, 0, list[i].name));
      var list2 = list[i].list;
      for (var j = 0; j < list2.length; j++) {
        temp.add(new Chapter(1, list2[j].id, list2[j].name));
      }
    }
    temp.setAll(0, chapters);

    chapters = temp;
    _bookTag.chapters = temp;
    SpUtil.putString(_bookInfo.Id.toString(), jsonEncode(_bookTag));
    //书的最后一章
    if (_bookInfo.CId == -1) {
      _bookTag.cur = chapters.length - 1;
      value = _bookTag.cur.toDouble();
    }
  }

  loadChapter(flag) async {
    //flage =g
    if (flag == 1) {
      //f g  g==1 forward =0 back
      getBookChapter(1, 1);
      //预加载下一章
      getBookChapter(0, 1);
    } else {
      getBookChapter(1, 0);
      //预加载上一章
      getBookChapter(0, 0);
    }
    value = _bookTag.cur.toDouble();
  }

//f 1 加载  g 1 前进
  getBookChapter(f, g) async {
    //f==0 是预加载
    if (f == 0) {
      int temp = 0;
      if (g == 1) {
        temp = _bookTag.cur + 1;
        if (temp == chapters.length) {
          return;
        }
        var chapter = chapters[temp];
        while (chapter.hasContent == 0) {
          temp += 1;
          if (temp == chapters.length) {
            break;
          }
          chapter = chapters[temp];
        }
      } else {
        temp = _bookTag.cur - 1;
        if (temp < 0) {
          return;
        }
        var chapter = chapters[temp];
        while (chapter.hasContent == 0) {
          temp -= 1;
          if (temp < 0) {
            return;
          }
          chapter = chapters[temp];
        }
      }
      justDown(temp, temp + 1);
    } else {
      var chapter = chapters[_bookTag.cur];
      while (chapter.hasContent == 0) {
        if (g == 1) {
          int tem = _bookTag.cur + 1;
          if (tem >= chapters.length) {
            Toast.show('已经是最后一页');
            return;
          } else {
            _bookTag.cur += 1;
          }
        } else {
          int tem = _bookTag.cur - 1;
          if (tem < 0) {
            _bookTag.cur += 1;
            Toast.show('已经是第一页');
            return;
          } else {
            _bookTag.cur -= 1;
          }
        }
        chapter = chapters[_bookTag.cur];
      }
      int i = _bookTag.cur;
      int id = chapters[i].id;
      if (SpUtil.haveKey(id.toString())) {
        _bookTag.content = SpUtil.getString(id.toString());
        if (SpUtil.haveKey('pages' + chapters[i].id.toString())) {
          _bookTag.pageOffsets =
              SpUtil.getString('pages' + chapters[i].id.toString())
                  .split('-')
                  .map((f) => int.parse(f))
                  .toList();
        } else {
          _bookTag.pageOffsets = ReaderPageAgent.getPageOffsets(
              SpUtil.getString(id.toString()), contentH, contentW, fontSize);
        }
      } else {
        var url = Common.bookContentUrl +
            _bookInfo.Id.toString() +
            "/" +
            id.toString() +
            ".html";
        Response response = await Util(context).http().get(url);
        String content = jsonDecode(response.data)['data']['content'];
        content = content.replaceAll("\r\n　　\r\n", "\n");
        if (content.startsWith('\n') || content.startsWith('\r\n')) {
          content = content.substring(1).trim();
        }
        if (content.startsWith('\r\n')) {
          content = content.substring(2).trim();
        }
        _bookTag.content = content;
        SpUtil.putString(id.toString(), content);
        _bookTag.pageOffsets = ReaderPageAgent.getPageOffsets(
            content, contentH, contentW, fontSize);
        SpUtil.putString('pages' + chapters[i].id.toString(),
            _bookTag.pageOffsets.join('-'));
        chapters[i].hasContent = 2;
      }
//上一章 需要显示 不是第一章
      if (g == 0 && f == 1 && _bookTag.cur > 0) {
        _bookTag.index = _bookTag.pageOffsets.length - 1;
        fix = !fix;
      }
      if (mounted) {
        setState(() {});
      }
      _pageController.jumpToPage(_bookTag.index);
    }
  }

  justDown(start, end) async {
    for (var i = start; i < end;) {
      Chapter cpt = chapters[i];
      if ((!SpUtil.haveKey(cpt.id.toString())) && cpt.hasContent != 0) {
        var url = Common.bookContentUrl +
            _bookInfo.Id.toString() +
            "/" +
            cpt.id.toString() +
            ".html";
        Response response = await Util(null).http().get(url);
        String content = jsonDecode(response.data)['data']['content'];
        content = content
            .replaceAll("\r\n　　\r\n", "\n")
            .replaceAll('“', '')
            .replaceAll('”', '');
        if (content.startsWith("\r\n")) {
          content = content.substring(4).trim();
        }
        if (content.startsWith('\n')) {
          content = content.substring(1);
        }
        SpUtil.putString(cpt.id.toString(), content);
        SpUtil.putString(
            'pages' + chapters[i].id.toString(),
            ReaderPageAgent.getPageOffsets(
                    content, contentH, contentW, fontSize)
                .join('-'));
        chapters[i].hasContent = 2;
        print('${chapters[i].name} 下载成功');
      }
      i++;
    }
  }

//prepage
  prePage() {
    var temp = _bookTag.index - 1;
    if (temp >= 0) {
      _bookTag.index = temp;
      _pageController.jumpToPage(_bookTag.index);
    } else {
      int temp = _bookTag.cur - 1;
      if (temp < 0) {
        Toast.show('已经是第一页');
      } else {
        _bookTag.cur -= 1;
        loadChapter(0);
      }
    }
  }

  //nextpage
  nextPage() {
    var temp = _bookTag.index + 1;
    if (temp < _bookTag.pageOffsets.length) {
      _bookTag.index = temp;
      _pageController.jumpToPage(_bookTag.index);
    } else {
      int temp = _bookTag.cur + 1;
      if (temp == chapters.length) {
        Toast.show('已经是最后一页');
      } else {
        _bookTag.cur += 1;
        _bookTag.index = 0;
        loadChapter(1);
      }
    }
    setState(() {});
  }

//上一章 下一章
  void changePage(BuildContext context, TapDownDetails details) {
    var wid = MediaQuery.of(context).size.width;
    var hei = MediaQuery.of(context).size.height;
    var space = wid / 3;
    var spaceY = hei / 3;
    var curWid = details.localPosition.dx;
    var curHeg = details.localPosition.dy;

    setState(() {
      if (curWid > 0 && curWid < space) {
        prePage();
      } else if ((curWid > space && curWid < 2 * space) &&
          (curHeg < 2 * spaceY)) {
        //弹出底部栏
        myshowModalBottomSheet(
            context: context,
            elevation: 0,
            builder: (BuildContext bc) {
              return StatefulBuilder(
                builder: (context, state) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          SizedBox(
                            width: 1,
                          ),
                          InkWell(
                            child: Container(
                              alignment: Alignment.center,
                              height: 50,
                              child: Text(
                                "上一章",
                                maxLines: 1,
                                style: TextStyle(color: Colors.blue),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onTap: () {
                              _bookTag.index = 0;
                              _bookTag.cur -= 1;
                              loadChapter(0);
                            },
                          ),
                          Slider(
                            value: value,
                            max: (chapters.length - 1).toDouble(),
                            min: 0.0,
                            onChanged: (newValue) {
                              int temp = newValue.round();
                              _bookTag.cur = temp;
                              loadChapter(1);

                              state(() {
                                ///为了区分把setState改个名字
                                value = _bookTag.cur.toDouble();
                              });
                            },
                            label: '${chapters[_bookTag.cur].name} ',
                            divisions: chapters.length,
                            semanticFormatterCallback: (newValue) {
                              return '${newValue.round()} dollars';
                            },
                            activeColor: Colors.lightBlue,
                            inactiveColor: Colors.grey,
                          ),
                          InkWell(
                            child: Container(
                              alignment: Alignment.center,
                              height: 50,
                              child: Text(
                                "下一章",
                                maxLines: 1,
                                style: TextStyle(color: Colors.blue),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onTap: () {
                              _bookTag.cur =
                                  (_bookTag.cur + 1) <= chapters.length - 1
                                      ? (_bookTag.cur + 1)
                                      : chapters.length - 1;
                              _bookTag.index = 0;
                              loadChapter(1);
                            },
                          ),
                          SizedBox(
                            width: 1,
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          SizedBox(
                            width: 1,
                          ),
                          InkWell(
                            child: Container(
                              alignment: Alignment.center,
                              height: 50,
                              child: Text(
                                "目录",
                                maxLines: 1,
                                style: TextStyle(color: Colors.blue),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _globalKey.currentState.openDrawer();
                            },
                          ),
                          IconButton(
                            icon: ImageIcon(
                              AssetImage("images/font_jia.png"),
                              color: Colors.blue,
                            ),
                            onPressed: () async {
                              state(() {
                                ///为了区分把setState改个名字
                                fontSize += 1;
                              });
                              setState(() {
                                _bookTag.index = 0;
                                _bookTag.pageOffsets =
                                    ReaderPageAgent.getPageOffsets(
                                        _bookTag.content,
                                        contentH,
                                        contentW,
                                        fontSize);
                              });
//                              changeCachePages();
                            },
                          ),
                          Container(
                            alignment: Alignment.center,
                            height: 50,
                            child: Text(
                              fontSize.toString(),
                              style: TextStyle(
                                  color: Colors.blueAccent, fontSize: 17),
                            ),
                          ),
                          IconButton(
                            icon: ImageIcon(
                              AssetImage("images/font_jian.png"),
                              color: Colors.blue,
                            ),
                            onPressed: () async {
                              state(() {
                                ///为了区分把setState改个名字
                                fontSize -= 1;
                                setState(() {
                                  _bookTag.index = 0;
                                  _bookTag.pageOffsets =
                                      ReaderPageAgent.getPageOffsets(
                                          _bookTag.content,
                                          contentH,
                                          contentW,
                                          fontSize);
                                });
                              });
//                              changeCachePages();
                            },
                          ),
                          InkWell(
                            child: Container(
                              alignment: Alignment.center,
                              height: 50,
                              child: Text(
                                "缓存",
                                maxLines: 1,
                                style: TextStyle(color: Colors.blue),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onTap: () {
                              showModalBottomSheet(
                                  context: context,
                                  builder: (BuildContext bc) {
                                    return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          InkWell(
                                            child: Container(
                                              alignment: Alignment.center,
                                              height: 50,
                                              child: Text(
                                                "从当前章节缓存",
                                                maxLines: 1,
                                                style: TextStyle(
                                                    color: Colors.blue),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            onTap: () async {
                                              justDown(_bookTag.cur,
                                                  chapters.length);

                                              Navigator.pop(context);
                                            },
                                          ),
                                          InkWell(
                                            child: Container(
                                              alignment: Alignment.center,
                                              height: 50,
                                              child: Text(
                                                "全本缓存",
                                                maxLines: 1,
                                                style: TextStyle(
                                                    color: Colors.blue),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            onTap: () async {
                                              justDown(0, chapters.length);
                                              Navigator.pop(context);
                                            },
                                          ),
                                        ]);
                                  });
                            },
                          ),
                          SizedBox(
                            width: 1,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            });
      } else {
        nextPage();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Scaffold(
      backgroundColor: Colors.transparent,
      key: _globalKey,
      drawer: Drawer(
        child: ChapterView(
            chapters, _bookInfo.Id.toString(), _bookTag.cur, _bookInfo.Name),
      ),
      body: Stack(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
                image: DecorationImage(
                    image: AssetImage("images/read_bg.jpg"),
                    fit: BoxFit.cover)),
            child: MyPageView.builder(
              controller: _pageController,

              physics: AlwaysScrollableScrollPhysics(),
              itemBuilder: (BuildContext context, int index) {
                return _getContent()[index];
              },
              //条目个数
              itemCount: _bookTag.pageOffsets.length,
              onPageChanged: (i) {
                if (fix) {
                  _bookTag.index = i;
                  setState(() {});
                } else {
                  fix = !fix;
                }
              },
            ),
            padding: EdgeInsets.only(
                bottom: 25, top: ScreenUtil.getStatusBarH(context) + 30),
          ),
          Container(
            padding: EdgeInsets.only(
                left: 10,
                right: 10,
                bottom: 1,
                top: ScreenUtil.getStatusBarH(context) - 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  chapters.length > 0 ? chapters[_bookTag.cur].name : '',
                  style: TextStyle(fontSize: 16, color: Colors.black),
                ),
                Expanded(child: Container()),
                Row(
                  children: <Widget>[
                    Expanded(child: Container()),
                    Text(
                      _bookTag.pageOffsets == null
                          ? ''
                          : '第${_bookTag.index + 1}/${_bookTag.pageOffsets.length}页',
                      style: TextStyle(fontSize: 13, color: Colors.black),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  _getContent() {
    List<Widget> contents = [];
    for (var i = 0; i < _bookTag.pageOffsets.length; i++) {
      var content = _bookTag.stringAtPageIndex(i);
      if (content.startsWith('\n') || content.startsWith('\r\n')) {
        content = content.substring(1).trim();
      }
      if (content.startsWith('\r\n')) {
        content = content.substring(2).trim();
      }

      contents.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails details) {
            changePage(context, details);
          },
          child: Container(
              padding: EdgeInsets.only(
                right: 10,
                left: 10,
              ),
              height: double.infinity,
              width: double.infinity,
              child: Text(
                content,
                style: TextStyle(
                    fontSize: fontSize / Screen.textScaleFactor,
                    color: Colors.black),
              )),
        ),
      );
    }

    return contents;
  }

  _changePage(int page) {
    if (page > 0) {
      nextPage();
    } else {
      prePage();
    }
  }
}

class ChapterView extends StatefulWidget {
  List<Chapter> chapters = [];
  String bookId;
  int cur;
  String bookName;

  ChapterView(this.chapters, this.bookId, this.cur, this.bookName);

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return new ChapterViewItem(bookId, cur, chapters, bookName);
  }
}

class ChapterViewItem extends State<ChapterView> {
  List<Chapter> chapters = [];
  String bookId;
  int cur;
  String bookName;
  ScrollController _scrollController = new ScrollController();

  double ITEM_HEIGH = 50.0;
  int ii = 0;
  bool up = false;
  int curIndex = 0;
  bool showToTopBtn = false; //是否显示“返回到顶部”按钮
  ChapterViewItem(this.bookId, this.cur, this.chapters, this.bookName);

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    _scrollController.dispose();
  }

  @override
  void initState() {
    // TODO: implement initState
    var widgetsBinding = WidgetsBinding.instance;
    widgetsBinding.addPostFrameCallback((callback) {
      scrollTo();
    });
    //监听滚动事件，打印滚动位置
    _scrollController.addListener(() {
      if (_scrollController.offset < ITEM_HEIGH * 8 && showToTopBtn) {
        setState(() {
          showToTopBtn = false;
        });
      } else if (_scrollController.offset >= 1000 && showToTopBtn == false) {
        setState(() {
          showToTopBtn = true;
        });
      }
    });
  }

//滚动到当前阅读位置
  scrollTo() async {
    if (_scrollController.hasClients) {
      curIndex = cur - 8;
      await _scrollController.animateTo((cur - 8) * ITEM_HEIGH,
          duration: new Duration(microseconds: 1), curve: Curves.ease);
    }
  }

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    Widget listView = new ListView.builder(
      controller: _scrollController,
      itemExtent: ITEM_HEIGH,
      itemBuilder: (context, index) {
        var title = chapters[index].name;
        var has = chapters[index].hasContent;
        padding:
        EdgeInsets.all(16.0);
        return ListTile(
          title: getTitle(title, has),
          trailing: new Text(
            has == 2 ? "已缓存" : "",
            style: TextStyle(fontSize: 8, color: Colors.grey),
          ),
          selected: index == cur,
          onTap: () {
            if (has > 0) {
              //不是卷目录
              Navigator.of(context).pop();
              eventBus.fire(new ChapterEvent(index));
            }
          },
        );
      },
      itemCount: chapters.length,
    );

    return Scaffold(
      appBar: AppBar(
        title: new Text(
          bookName,
          style: TextStyle(
              color: Store.value<AppThemeModel>(context)
                  .getThemeData()
                  .iconTheme
                  .color,
              fontSize: 16.0),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: Scrollbar(
        child: listView,
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: topOrBottom,
          child: Icon(
            showToTopBtn ? Icons.arrow_upward : Icons.arrow_downward,
          )),
    );
  }

  topOrBottom() async {
    if (_scrollController.hasClients) {
      int temp = showToTopBtn ? 1 : chapters.length - 8;
      await _scrollController.animateTo(temp * ITEM_HEIGH,
          duration: new Duration(microseconds: 1), curve: Curves.ease);
    }
  }

  getTitle(title, has) {
    Widget widget;
    if (has == 0) {
      widget = new Text(
        title,
        style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
      );
    } else {
      widget = new Text(
        title,
        style: TextStyle(fontSize: 12),
      );
    }
    return widget;
  }
}
