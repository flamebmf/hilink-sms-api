#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

use LWP::UserAgent;
use HTTP::Request;
use HTML::Entities;
use Time::HiRes qw (time);
use POSIX;
use Data::Dumper;
use utf8;
use Encode;

# Собственно функция отправки СМС
sub SendSMS {
        my $ip = shift;
        my $phone = shift;
        my $msg = shift;

        # Формируем запрос
        my $request_data = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>";
        $request_data .= "<request><Index>-1</Index><Phones><Phone>";
        $request_data .= encode_entities($phone);
        $request_data .= "</Phone></Phones><Sca></Sca><Content>";
        $request_data .= encode_entities(decode("utf8", $msg));
        $request_data .= "</Content><Length>";
        $request_data .= length($msg);
        $request_data .= "</Length><Reserved>1</Reserved><Date>";
        $request_data .= encode_entities(strftime("%Y-%m-%d %H:%M:%S", localtime()));
        $request_data .= "</Date></request>";

        # Сначала попробуем получить авторизационный токен и идентификатор сессии
        # ВАЖНО! Отсутствие токена не всегда является проблемой!
        my $ua = LWP::UserAgent->new(
                agent => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.132 Safari/537.36"
        );
        my $response = $ua->get("http://$ip/api/webserver/SesTokInfo");
        my $token;
        my $session_id;
        if ($response->content =~ m{<TokInfo>(.+?)</TokInfo>}) {
                $token = $1;
        }
        if ($response->content =~ m{<SesInfo>(.+?)</SesInfo>}) {
                $session_id = $1;
                $session_id = "SessionID=$session_id" unless $session_id =~ /^SessionID=/;
        }

        # Создаём запрос
        my $req = HTTP::Request->new("POST" => "http://$ip/api/sms/send-sms");
        # Указываем основные заголовки
        $req->header("Origin" => "http://$ip");
        $req->header("Referer" => "http://$ip/html/smsinbox.html");
        $req->header("Content-Type" => "text/xml; charset=UTF-8");
        $req->header("X-Requested-With" => "XMLHttpRequest");
        # Если есть токен то добавляем ещё и его
        $req->header("__RequestVerificationToken" => $token) if $token;
        # Если есть идентификатор сессии
        $req->header("Cookie" => $session_id) if $session_id;
        # Добавляем данные к запросу
        $req->content($request_data);

        # Выполняем запрос
        $response = $ua->request($req);

        # Обрабатываем результат
        return $response->is_success && $response->content =~ m{<response>OK</response>}s ? 1 : 0;
}
my $ip = shift @ARGV;
my $phone = shift @ARGV;
my $msg = shift @ARGV;

if (!defined($msg)) {
        print "Usage: $0 <Modem IP> <Phone Number> <Message>\n";
        exit();
}

# $ip не валидируем, потому что там может быть и доменное имя (например m.home)
# пробуем валидировать $phone:
if ($phone !~ m{^(?:\+7|8)?\d{10}$}) {
        print "Bad phone number!\n";
        exit();
}
# $msg не валидируем. Если до сюда дошли то значит он не пуст и этого достаточно

my $result = SendSMS($ip, $phone, $msg);
print $result ? "OK\n" : "ERROR\n";
