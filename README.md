rbenv と bundler が導入されている前提で

```
# Bundler で gem インストール
bundle install
# インストールした gem の確認
bundle exec gem list
```
```
# Usage を表示
ruby ./lib/simple_crawler.rb -h
# dry run モード実行。コマンドラインオプションと設定ファイルの内容がロギングされるだけ。
ruby ./lib/simple_crawler.rb -c ./conf/sample.conf  -l info --no-run
# run モード実行。sample.conf を使用。
ruby ./lib/simple_crawler.rb -c ./conf/sample.conf  -l info --run
```
