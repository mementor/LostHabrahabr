#!/usr/bin/perl

use strict;
use warnings;
use Encode;

use LWP::UserAgent;
use HTTP::Request;
use HTML::TreeBuilder;
use Date::Language;
use Redis;

my $nextPageUrl = "http://habrahabr.ru/posts/collective/all/page1/";

my $redis = Redis->new(server => "78.47.99.227:16777", encoding => undef);
my $tree;
do {
	$tree = getTree($nextPageUrl);
	#print "[$nextPageUrl] -- new iteration\n";
	for my $a ($tree->look_down(class => "post_title")) {
		#print "in for $a\n";
		my $href = normalizeText($a->attr("href"));
		#print "href -- $href\n";
		my $title = normalizeText($a->as_text);

		my %postData = getPostData($href);
		print "[$nextPageUrl] -- $href\n";

		$href =~ /\/(\d+)\/$/;
		my $id = $1;
		if (! $redis->exists($id.":status")) {
			$redis->set($id.":status", $postData{"status"});
			$redis->set($id.":href", $href);
			$redis->set($id.":html_post", $postData{"html_post"});
			$redis->set($id.":published", $postData{"published"});
		}
	}
	my $nextPage = $tree->look_down(id => "next_page");
	if($nextPage) {
		$nextPageUrl = "http://habrahabr.ru".$nextPage->attr("href");
	} else {
		$nextPageUrl = undef;
	}
} while ($nextPageUrl);


sub getPostData {
	my $url = shift;
	my %ret;
	my $postTree = getTree($url);
	my $htmlPost = $postTree->look_down(class => "content html_format");
	if ($htmlPost) {
		$ret{"status"} = "live";
		$ret{"html_post"} = normalizeText($htmlPost->as_HTML);
		my $pubDate = $postTree->look_down(class => "published");
		$ret{"published"} = getUnixDate(normalizeText($pubDate->as_text));
	} else {
		my @piss = $postTree->look_down(_tag => "p");
		if ($piss[1]) {
			normalizeText($piss[1]->as_text) =~ /^Автор переместил топик в черновики.$/ ? $ret{"status"} = "draft" : $ret{"status"} = "undef";
		} else {
			$ret{"status"} = "error"
		}
	}
	return %ret;
}

sub normalizeText {
	my $str = shift;
	HTML::Entities::decode_entities($str);
	utf8::encode($str);
	return $str;
}

sub getTree {
	my $url = shift;
	my $ua = LWP::UserAgent->new;
	my $req = HTTP::Request->new(GET=>$url);
	my $resp = $ua->request($req);
	my $tree = HTML::TreeBuilder->new;

	return $tree->parse_content(Encode::decode_utf8 $resp->content);
}

sub getUnixDate {
	my $dirtyDate = shift;
	my $ret;

	my $lang = Date::Language->new('Russian_koi8r');
	my $firstPart;
	if($dirtyDate =~ /^сегодня/) {
		$firstPart = Encode::decode("koi8-r", $lang->time2str("%d %B %Y",time));
	} elsif ($dirtyDate =~ /^вчера/) {
		$firstPart = Encode::decode("koi8-r", $lang->time2str("%d %B %Y",time-86400));
	} else {
		$dirtyDate =~ /^(.+) /;
		$firstPart = $1;

		# TODO: its realy dirty, rework later
		$firstPart =~ /\s(\w)/;
		my $uc = uc $1;
		$firstPart =~ s/\s\w/ $uc/g;
	}
	$dirtyDate =~ /(\d\d):(\d\d)$/;
	$ret = "$firstPart $1:$2";
	$ret = $lang->str2time(Encode::encode("koi8-r", $ret));
	return $ret;
}