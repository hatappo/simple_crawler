* [rbenv](http://dev.classmethod.jp/server-side/language/build-ruby-environment-by-rbenv/) と [Bundler](http://shokai.org/blog/archives/7262) が導入されていて、[Phantom.js](http://nigohiroki.hatenablog.com/entry/2012/12/14/004915) がインストールされていること。
```
$ rbenv -v
rbenv 0.4.0
$ bundler -v
Bundler version 1.8.2
$ phantomjs -v
2.0.0
```

* 動かし方
```
git clone https://github.com/hatappo/simple_crawler.git
cd ./simple_crawler
```
```
# Bundler で gem インストール
bundle install
# インストールした gem の確認
bundle exec gem list
```
```
# Usage を表示
ruby ./lib/simple_crawler.rb -h
# dry run 。コマンドラインオプションと設定ファイルの内容がロギングされるだけ。
ruby ./lib/simple_crawler.rb -c ./conf/sample.conf -l info --no-run
# 実行。sample.conf を使用。
ruby ./lib/simple_crawler.rb -c ./conf/sample.conf -l info --run
```
