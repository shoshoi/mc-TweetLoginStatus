#!/usr/bin/perl
use strict;
use Switch;
use File::Basename;
use Net::Twitter;
use utf8;
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

# 終了コードの定義(0～99:正常終了 / 100～:エラー終了 / 900～:異常終了)
use constant {
   # 正常終了
   TWEET_SUCCESS        => 0,    # ツイート成功
   SAME_BEFORE_POST     => 1,    # 前回と同じツイート
   NORMAL_MESSAGE_END   => 99,   # 正常メッセージここまで(判定用のため，メッセージテキストは定義しない)

   # エラー終了
   SHELL_ERR            => 100,  # シェル実行エラー
   MC_COMMAND_ERR       => 101,  # Minecraftコマンド実行エラー
   TWITTER_POST_ERR     => 102,  # ツイッターポストエラー
   FILE_IO_ERR          => 103,  # ファイルIOエラー
   FORMAT_CONV_ERR      => 104,  # メッセージフォーマット変換処理失敗
   ERROR_MESSAGE_END    => 199,  # エラーメッセージここまで(判定用のため，メッセージテキストは定義しない)

   # 異常終了(perlスクリプトそのもののエラー)
   MESSAGE_ERROR        => 900   # メッセージが見つからない
};

# メッセージテキストの定義
my %Messages = (
   # 正常終了メッセージ
   TWEET_SUCCESS()      => 'ツイートしました。',
   SAME_BEFORE_POST()   => '前回のツイートからログイン状況が更新されていないため，ツイートを中断します。',
#  NORMAL_MESSAGE_END() => 判定用のため，メッセージテキストは定義しない。

   # エラー終了メッセージ
   SHELL_ERR()          => 'シェル実行エラーです。ログファイルを確認して下さい。',
   MC_COMMAND_ERR()     => 'Minecraftコマンド実行エラーです。ログファイルを確認して下さい。',
   TWITTER_POST_ERR()   => 'ツイッターへの投稿に失敗しました。アカウントの状況を確認して下さい。',
   FILE_IO_ERR()        => 'ファイルの入出力に失敗しました。',
   FORMAT_CONV_ERR()    => 'Minecraftコマンド実行結果テキストの，出力形式への変換に失敗しました。',
#  ERROR_MESSAGE_END()  => 判定用のため，メッセージテキストは定義しない。

   # 異常終了メッセージ
   MESSAGE_ERROR()      => '定義されていないメッセージです。'
);

# 出力ファイルパスの宣言
my $LOG_FILE    = $ENV{MC_LOGINSTAT_LOG_FILE};
my $BEFORE_FILE = $ENV{MC_LOGINSTAT_BEFORE_FILE};

# Twitterアクセス情報の定義
my $consumer_key        = $ENV{MC_TWEET_CONSUMER_KEY};
my $consumer_secret     = $ENV{MC_TWEET_CONSUMER_SECRET};
my $access_token        = $ENV{MC_TWEET_ACCESS_TOKEN};
my $access_token_secret = $ENV{MC_TWEET_ACCESS_TOKEN_SECRET};

# 変数の定義
my $rtncode = 0;    # 終了コード
my $tweet_str = ""; # ツイッター投稿文字列


# Minecraftコマンドを実行し，ログインリストを取得
my @results = `sudo /etc/init.d/minecraft command list | sed 's/ /_/g'`;

if($rtncode = com_isError(@results)){
   # コマンド実行エラー、ログを出力する。
   MessageOut($rtncode);
   if($rtncode = printLog(@results)){
      # IOエラー
      MessageOut($rtncode);
   }
   ExitCommand($rtncode);
}

# 実行結果を出力形式に編集し、メッセージ変数に格納
my $tweet_str = convFormat(@results[1]);
if($tweet_str == FORMAT_CONV_ERR){
   MessageOut($tweet_str);
   ExitCommand($tweet_str);
}
chomp($tweet_str);

if($rtncode = eqBefore($tweet_str)){
   # 前回のツイート時点と人数が変わっていない場合ツイートせず終了
   MessageOut($rtncode);
   ExitCommand($rtncode);
}

# Twitterアクセスオブジェクト生成
my $handle = Net::Twitter->new({
    traits => [qw/OAuth API::RESTv1_1/],
    consumer_key => $consumer_key,
    consumer_secret => $consumer_secret,
    access_token => $access_token,
    access_token_secret => $access_token_secret});

# ツイート実行
my $rtncode = $handle->update({status=>$tweet_str});

# 終了処理
if($rtncode){
   # ツイート成功
   $rtncode = TWEET_SUCCESS;
   MessageOut($rtncode);
   if($rtncode = makeBeforeLog($tweet_str)){
      # IOエラー
      MessageOut($rtncode);
   }
}else{
   # ツイート失敗
   $rtncode = TWITTER_POST_ERR;
   MessageOut($rtncode);
}

ExitCommand($rtncode);

##################################################
# ■メッセージ出力処理
#
#   引数  :$rtn_no(終了コード)
#   戻り値:$rtn_no(引数をそのまま返す)
#
#   処理概要:
#    1. 終了コードに対応するメッセージテキストを，以下の出力先に出力する。
#     (a)終了コードが正常(NORMAL_MESSAGE_END未満)のとき，標準出力
#     (b)終了コードがエラー(NORMAL_MESSAGE_END以上)のとき，標準エラー出力
#
sub MessageOut {
   my $rtn_no = shift;
   if(!exists($Messages{$rtn_no})){
      exit 256 if(!exists($Messages{MESSAGE_ERROR()}));
      $rtn_no = MessageOut(MESSAGE_ERROR);
   }

   # 関数呼び出し元の情報を取得
   my ($pkg, $file, $line) = caller;
   $file = basename($file);

   # メッセージ出力処理
   if ($rtn_no < NORMAL_MESSAGE_END) {
      # 標準メッセージ出力
      print $Messages{$rtn_no}."\n";
   } elsif($rtn_no < ERROR_MESSAGE_END) { 
      # エラーメッセージ出力
      print STDERR "error(${rtn_no}):".$Messages{$rtn_no}."\n";
      print STDERR "line number : ${file}(${line})\n";
   }else{
      # 異常終了メッセージ出力
      print STDERR "fatal error(${rtn_no}):".$Messages{$rtn_no}."\n";
      print STDERR "line number : ${file}(${line})\n";
      ExitCommand($rtn_no);
   }
   return $rtn_no;
}
##################################################
# ■プログラム終了処理
#
#   引数  :$rtn_no(終了コード)
#   戻り値:$rtn_noが正常(NORMAL_MESSAGE_END未満)のとき，0
#          $rtn_noがエラー(NORMAL_MESSAGE_END以上)のとき，1
#          上記以外の時,256
#
#   処理概要:
#    正常終了の場合戻り値0，エラー終了の場合戻り値1，異常終了のとき256でプログラムを終了する。
#
sub ExitCommand {
   my $rtn_no = shift;
   if ($rtn_no < NORMAL_MESSAGE_END) {
      exit 0;
   } elsif($rtn_no < ERROR_MESSAGE_END) { 
      exit 1;
   } else {
      exit 256;
   }
}
##################################################
# ■コマンドエラー判定処理
#
#   引数  :@results(Minecraftコマンドの実行結果の文字列)
#   戻り値:シェル実行エラーのとき，SHELL_ERR
#          Minecraftコマンド実行エラーのとき，MC_COMMAND_ERR
#
#   処理概要:
#    1.コマンドの実行結果が正しいか判定する。以下の場合エラー
#     (a)コマンド実行結果が1行未満
#        (実行結果がない。=>シェルの実行に失敗している)
#     (b)上記以外のとき，コマンド実行結果の1行目が，Minecraftコマンド実行成功時の
#        メッセージと一致しない。
#        (Minecraftコマンド実行に失敗している)
#     (c)上記以外のとき，コマンド実行結果が2行未満
#        (Minecraftコマンド実行に成功しているが，listコマンドの結果が返っていない)
#
sub com_isError {
   my @results = @_; 

   if($#results < 1){
      # シェル実行エラー
      return SHELL_ERR;
   }
   if(@results[0] ne "minecraft_server.jar_is_running..._executing_command\n"){
      # minecraftコマンド実行エラー
      return MC_COMMAND_ERR;
   }
   if($#results < 2){
      # listコマンド実行エラー
      return MC_COMMAND_ERR;
   }
   return 0;
}
##################################################
# ■エラーログ出力処理
#
#   引数  :@results(Minecraftコマンドの実行結果の文字列)
#   戻り値:ログ出力成功時，0
#          ログ出力失敗時，FILE_IO_ERR
#
#   処理概要:
#    コマンドの実行結果を，エラーログファイルに出力する。
#
sub printLog {
   my @results = @_; 
   my $date = `date +"%Y/%m/%d %H:%M:%S"`;
   chomp($date);

   if(open(DATAFILE, ">>", $LOG_FILE)){
      return FILE_IO_ERR;
   }

   print DATAFILE "###### ${date} ######\n";
   foreach my $line (@results){
      print DATAFILE $line;
   }
   print DATAFILE "\n";
   close(DATAFILE);
   return 0;
}
##################################################
# ■listコマンドメッセージフォーマット変換処理
#
#   引数  :$str(listコマンドのメッセージ(英文))
#   戻り値:$strを出力形式(和文)に編集した文字列
#
#   処理概要:
#    listコマンドの結果を以下のように編集する。
#     (例)編集前:[21:33:39] [Server thread/INFO]: There are 5/20 players online:
#         編集後:[21:33:39] :現在 5 人のプレイヤーがログインしています。
#
sub convFormat {
   my $str = shift;
   my $rtn_code = 1;

   $rtn_code &= ($str=~ s/(?:_\[Server_thread\/INFO\])/ /g);
   $rtn_code &= ($str=~ s/(?:_There_are_)/現在 /g);
   $rtn_code &= ($str=~ s/(?:\/20_players_online:)/ 人のプレイヤーがログインしています。/g);

   if(!$rtn_code){
      return FORMAT_CONV_ERR;
   }

   return $str;
}
##################################################
# ■前回ツイートとの比較判定処理
#
#   引数  :$msg(ツイッター投稿メッセージ)
#   戻り値:ファイル読み込みに失敗した時，FILE_IO_ERR
#          $msgと前回ツイートの内容が同じ時，SAME_BEFORE_POST
#          それ以外は0
#
#   処理概要:
#    1. 前回のツイートをログファイルから読み込む
#    2. 今回のツイートから，日時(例)[21:00:00] を削除する。
#    3. 1の文字列と2の文字列を比較し，同じであればSAME_BEFORE_POSTを返す
#
sub eqBefore {
   my $msg = shift;
   my $rtncode = 0;
   my $beforestr = "";

   # 前回のメッセージを保存したファイルを読み込み
   if(!open(DATAFILE, "<", $BEFORE_FILE)){
      return FILE_IO_ERR;
   }
   binmode(DATAFILE, ":utf8");
   if (my $line = <DATAFILE>){
      chomp($line);
      $beforestr = $line
   }
   close(DATAFILE);

   $msg = substr($msg, 12);
   chomp($msg);

   if($beforestr eq $msg){
      # 前回メッセージと今回メッセージが同じならばツイートしない
      $rtncode = SAME_BEFORE_POST;
   }

   return $rtncode;
}
##################################################
# ■ツイート出力処理
#
#   引数  :$msg(ツイッター投稿メッセージ)
#   戻り値:ファイル読み込みに失敗した時，FILE_IO_ERR
#          それ以外は0
#
#   処理概要:
#    1. ツイートから，日時(例)[21:00:00] を削除する。
#    3. 1の文字列をログファイルに出力する。
#
sub makeBeforeLog {
   my $msg = shift;

   $msg = substr($msg, 12);
   chomp($msg);

   if(!open(DATAFILE, ">", $BEFORE_FILE)){
      return FILE_IO_ERR;
   }
   binmode(DATAFILE, ":utf8");
   print DATAFILE $msg."\n";
   close(DATAFILE);
   
   return 0;
}