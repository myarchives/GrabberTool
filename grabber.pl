use strict;
use warnings;
use v5.18;

use WWW::Mechanize;
use LWP::Simple;
use Cwd;
use File::Path qw(make_path remove_tree);
use FileHandle;

   ##########################
  #                        #
 #    WEB GRABBER TOOL    #
#                        #
########################

# CONSTANTS
my $WEB_URL = 'www.schenker.pl';
my $login_url = 'https://econnect.schenker.pl/login.php';
my $main_url = 'https://econnect.schenker.pl/';
my $fake_browser = 'Windows Mozilla';
my $manual_mode = 1;
my $range_mode = 0;
my $ref_default = '42710174';
my $search_time_limit = 5;
my $file_format = ".jpg";

# PAGE LOGIN INFO
my $user_name = 'HanSolo';
my $password = 'Admin123';

# GLOBAL VAR
my $num_of_img = 0;
my $img_dir = '';
my $ref = '';
my $top_ref;
my $bot_ref;
my $arg_ref;
my $mode;
my $infinity_run = 0;

# OTHER
my $web_storage;

sub do_the_job
{
    my ($mech, $ref) = @_;

    my $time_start = time();

    #Find all submits
    my @submits = $mech->find_all_submits();
    
    #Fill submit field
    $mech->field('ARG[ref]', $ref);    
    
    #Click "Szukaj"
    my $button_to_click = $submits[0]->{name};
    print "Searching images! Please Wait...\n";
    eval { $mech->click($button_to_click) };
    #print_status($mech, $button_to_click);
    
    #Get all links
    my @all_links = eval { $mech->find_all_links() };
     
    #Get only raport links
    my @rap_links;
    for(@all_links)
    {
        push (@rap_links, $_->[0]) if $_->[0] =~ /rap_obraz/i && $_->[0] !~ /arg_frag/i;
    }
    
    #Create final download links
    my @final_links;
    for(@rap_links)
    {
        push (@final_links, $main_url . $_);
    }
    
    #Get full page content
    my $page_content = $mech->content();
    my @page = split("\n", $page_content);
    
    #Get letter's unique reference
    my @letters_ref;
    my $take_ref = 0;
    for my $link(@rap_links)
    {
        $link =~ s/\D//g;
        
        for my $line(@page)
        {
            if ($take_ref)
            {
                if ($line =~ /$ref/)
                {
                    $line =~ s/\D//g;
                    $line = reverse $line;
                    chop $line;
                    $line = reverse $line;
                    chop $line;
                    
                    push (@letters_ref, $line);
                    $take_ref = 0;
                    last;
                }                
            }            
            if ($line =~ /$link/ )
            {
                $take_ref = 1;
            }            
        }            
    }
        
    #Get delivered day
    my @lines_with_deliver;
    my $deliver_boy = 0;
    
    for(my $i = 0; $i < scalar @page; $i++)
    {
        if (($page[$i] =~ /<td rowspan="1">[0-9]{4}-[0-9]+-[0-9]+/) && !$deliver_boy)
        {
            $deliver_boy = 1;
            $i++;            
        }
        if (($page[$i] =~ /<td rowspan="1">[0-9]{4}-[0-9]+-[0-9]+/) && $deliver_boy)
        {
            push (@lines_with_deliver, $page[$i]);            
            $deliver_boy = 0;
        }
    }
    
    #Get only date from lines    
    my @days;
    
    for(@lines_with_deliver)
    {
        $_ =~ s/<td rowspan="1">\d{4}-\d+-(\d+)<\/td>//;
        my $day = $1;
        push (@days, $day);
    }  
    
    #Download images
    print "Download images...\n";
    my $img_counter = 1;
    my $img_name;
    $num_of_img = scalar @final_links;
    my $letter_pos = 0;
    my $buffer_name = '';
    
    # create array of image descriptors
    my @img_desc;
    for (my $i = 0; $i < scalar @final_links; $i++)
    {        
        push(@img_desc, {
                            ref  => $letters_ref[$i],
                            link => $final_links[$i],
                            day  => $days[$i],
                            part => '',
                            name => ''
                        });
    }
    
    # finalize names
    for(my $i = 0; $i < scalar @img_desc; $i++)
    {
        my $buffer_desc = $img_desc[$i];
        my $part_num = 0;
            
        for(my $i2 = 1+$i; $i2 < scalar @img_desc; $i2++)
        {
            if ($buffer_desc->{ref} eq $img_desc[$i2]->{ref})
            {
                $part_num++;
                $img_desc[$i]->{part} = $part_num;
                $part_num++;
                $img_desc[$i2]->{part} = $part_num;
            }
        }
    }   
    
    for(@img_desc)
    {
        eval { $mech->get($_->{link}) };
        
        if(!$_->{part})
        {
            $_->{name} = $_->{ref} . " " . $_->{day} . $file_format;
        }
        else
        {
            $_->{name} = $_->{ref} . " " . $_->{day} . " cz." . $_->{part} . $file_format;
        }
        
        $mech->save_content($_->{name});     
    }
    print "Saving images\n";

    #Summary
    my $time_stop = time() - $time_start;    
    
    print <<SUM;
Run Time: $time_stop [s]
Number of grabbed images: $num_of_img
Path to files: $img_dir
SUM

}

sub go_to_przesylki
{
    my ($mech) = @_;    
    
    #Click "Raporty"
    eval { $mech->get('https://econnect.schenker.pl/rap.php') };
    print_status($mech, 'https://econnect.schenker.pl/rap.php' );
    
    #Click "Przesylki"
    $mech->get('https://econnect.schenker.pl/rap_lg.php');
    print_status($mech, 'https://econnect.schenker.pl/rap_lg.php' );    
}

sub print_status
{
    my ($mech, $link) = @_;
    
    #Print Status
    print "$link STATUS: ";
    my $status = $mech->success();
    print $status ? "OK" : ("ERROR: ", $mech->status());
    print "\n";
    
    return $status;
}

sub main()
{
    for(@ARGV)
    {
        if ($_ =~ /.n/i)
        {
            $mode = 'n';
        }
        if ($_ =~ /\d/)
        {
            $arg_ref = $_;
        }
        $infinity_run = -1;
    }
    
    print "GRABBER TOOL V1.0\n";
    
    my $mech = WWW::Mechanize->new();    
    #$mech->show_progress(1);
    
    #print "Available aliases for agent: ", $mech->known_agent_aliases(), "\n";
    $mech->agent_alias($fake_browser);
    print "FAKE_BROWSER: $fake_browser\n";
    
    $mech-> cookie_jar(HTTP::Cookies->new());    
   
    #Solve paths
    my $dir = getcwd;
    $img_dir = $dir . '/' . 'img';    
    make_path $img_dir unless -e $img_dir;
    chdir $img_dir;

    while ((($ref ne 'q') || ($ref ne 'Q')) && $infinity_run++) 
    {     
        #Read "referencja"
        if ($manual_mode)
        {
            print "Choose mode: <R>Range | <>Normal: ";
            chomp($mode = <>) unless $mode;

            if (($mode eq 'r') || ($mode eq 'R'))
            {
                print "Range Mode: ON\n";
                print "[Press <Q> to Quit] Referencja<WPROWADZ> od: ";
                chomp($bot_ref = <>);

                if (($bot_ref eq 'q') || ($bot_ref eq 'Q'))
                {
                    return 0;
                }

                print "[Press <Q> to Quit] Referencja<WPROWADZ> do: ";
                chomp($top_ref = <>);
                
                if (($top_ref eq 'q') || ($top_ref eq 'Q'))
                {
                    return 0;
                }

                for ($bot_ref; $bot_ref < $top_ref; $bot_ref++)
                {                    
                    #Go to page
                    $mech->get($login_url);    
                    print_status($mech, 'Zaloguj sie');
                    
                    #login
                    $mech->form_name('f1');
                    $mech->field('ARG[user]' => $user_name);
                    $mech->field('ARG[pass]' => $password);
                    eval { $mech->click('submit_loguj') };
                    print_status($mech, "Login");    
                    #print $mech->content();

                    go_to_przesylki($mech);

                    print "Szukam obrazow dla referencji nr: $bot_ref\n";
                    do_the_job($mech, $bot_ref); 

                    #logout
                    $mech->get('login.php?akcja=logout');
                    print_status($mech, 'Wyloguj sie');           
                }                
            }
            else
            {               
                print "Normal Mode: ON\n";
                print "[Press <Q> to Quit] Referencja<WPROWADZ>: ";
                                
                $arg_ref ? $ref = $arg_ref : chomp($ref = <>);
                #chomp($ref = <>) unless $arg_ref;

                if (($ref eq 'q') || ($ref eq 'Q'))
                {
                    return 0;
                }

                #Go to page
                $mech->get($login_url);    
                print_status($mech, 'Zaloguj sie');
                
                #login
                $mech->form_name('f1');
                $mech->field('ARG[user]' => $user_name);
                $mech->field('ARG[pass]' => $password);
                eval { $mech->click('submit_loguj') };
                
                my $login_attemptts = 0;
                while ((print_status($mech, "Login") != 1) && ($login_attemptts < 5))
                {
                    $login_attemptts++;
                    
                    eval { $mech->click('submit_loguj') };
                    
                    print "Login Error. Try to login again after 5 sec...\n";
                    print "$login_attemptts Login attempt\n";
                    sleep 5;
                }
                $login_attemptts = 0;
                
                print_status($mech, "Login");    
                #print $mech->content();

                go_to_przesylki($mech);

                print "Szukam obrazow dla referencji nr: $ref\n";
                do_the_job($mech, $ref);
            } 
        }
        else
        {
            print "Referencja domyslna: $ref_default\n";
            $ref = $ref_default;
            do_the_job($mech, $ref);
        }   
    }     
    
    #w8 screen
    local($|) = (1);
    print "Press any key to continue...";
    my $resp = <STDIN>;
}

# START
main();