#!/usr/local/bin/perl

use Sys::Hostname;
use Perl6::Slurp;
use JSON;
use Geo::WeatherNWS;
use strict;
use IO::Socket;
use IO::Select;
use IO::Pipe qw();
use IO::Handle;
use List::Util qw(shuffle);
use XML::LibXML;   
use URI::Escape;
use DateTime;

use DBI;

$|=1;
my $forever = 'yeah';

our $VERSION = "0.38";
our $password = shift || die('MySQL password not provided');
our $chan = shift || '#test';
our $iter = shift || 0;
our $me;

our $p = XML::LibXML->new;

our $sson = 0;
our $g_dbh;

MAINIRC: while ($forever)
{
	$me = 'cinci_pm_bot' . $iter;
	my $c;
	eval {
	$c = IO::Socket::INET->new( PeerAddr=>'irc.perl.org',
				      PeerPort=>'6667',
				      Proto=>'tcp',
				      Timeout=>'30') || print "Error! $!\n";
	};

        binmode($c, ':utf8');

	if ($@)
	{
		warn "Server connection has gone away, will reconnect in 10 seconds";
		sleep 10;

		next(MAINIRC);
	}

        print $c "NICK $me\r\n";
        print $c "USER $me " . hostname . " irc.perl.org :Cinci Bot\r\n";
        print $c "JOIN $chan\r\n";
	print $c "PRIVMSG $chan :bot.pl version $VERSION - type \"$me\" (no quotes) for command list\r\n";
	#io sel setup
	my $sock = IO::Select->new();
	$sock->add($c);
	$sock->add(\*STDIN);
	my $kick = 0;
	
	if (my @handles = $sock->can_read(1))
	{
		print "All handles ready";
	}

	while ( my @ready = $sock->can_read )
	{
	eval {	
#		local $SIG{ALRM} =  sub { $kick = 1; die "pow\n"; };#<Undo
#		alarm 10;

		foreach my $handle (@ready)
		{
			if ($handle == $c)
			{
				# this is from the irc onnection
				my $buffer;
				sysread($c,$buffer,4096);
				if (!$buffer)
				{
					warn "Server connection has gone away, will reconnect in 10 seconds";
#					alarm 0;
					sleep 10;
					
					next(MAINIRC);
				}
				my @lines = split(/\n/,$buffer);
				foreach my $line (@lines)
				{
					eval {
						&parse_serverline($c,$line);
					};

					if ($@)
	                                {
        	                                warn "$@ -  will reconnect in 10 seconds";
#						alarm 0;
                	                        sleep 10;
                                	        next(MAINIRC);
                                	}
				}
			}

=pod

			elsif ($handle == $tick)
			{
                               	my $buffer;
		                sysread($handle,$buffer,4096);
				
				if ($buffer)
				{
					warn "pinged for accounting ($buffer)";
				}
				else
				{
					print "z";
					sleep 1;
				}
			}

=cut

			else
			{
				# we typed soemthing
				my $buffer = <STDIN>;
				if ($buffer)
				{
					if ($buffer =~ /^\/me/)
					{
						$buffer =~ s/^\/me //g;
					}
					else
					{
						&local_echo($buffer);
						print $c "PRIVMSG $chan :$buffer";
					}
				}
			}
		}
#		alarm 0;	
	};
	if ($@ =~ /pow/)
	{
		print "Seems alarmy: " . $@;
	}
	else
	{
		print $@ . "\n";
	}
	}
}

sub get_dbh
{
        eval {
                $g_dbh->do("select now()");
        };

        if ($@)
        {
                warn "Connecting to db on localhost";
                $g_dbh = DBI->connect("DBI:mysql:database=irclogs;host=localhost","irclog",$password,{'RaiseError' => 1});
        }

        return $g_dbh;
}

sub local_echo
{
    my $message = shift;
    return;
	my $dbh = &get_dbh;
                        
	my $userref = $dbh->selectrow_hashref("select * from irc_user where shortname=?",undef,$me);
	my $chanref = $dbh->selectrow_hashref("select * from irc_channel where name=?",undef,$chan);

	if (!$chanref->{id})
	{
		$dbh->do("insert into irc_channel (name) values (?)",undef,$chan);
		$chanref = $dbh->selectrow_hashref("select * from irc_channel where name=?",undef,$chan);
	}

	$dbh->do("insert into irc_log (irc_channel_id,irc_user_id,irc_command,message,logged_at) values (?,?,?,?,now())",undef,
			$chanref->{id},$userref->{id},'PRIVMSG',$message);
}


sub parse_serverline
{
	my ($sock,$serverline) = @_;	
        die "*** connection to server lost\n" if ($serverline eq "");
	# parse
        $serverline = "server $serverline" unless $serverline =~ /^:/;
        my ($who, $cmd, $args) = split(/ /, $serverline, 3);
        $who =~ s/^://;
        $cmd =~ tr/a-z/A-Z/;
        $args =~ s/^://;

	my $dbh = &get_dbh();

	if ($cmd =~ /\d+/)
	{
            print $cmd;
		if ($cmd == 311)
		{
			# serverline :irc.whapps.com 311 cinci_pm_bot_1 console0 ~console0 10.0.2.11 * :Marcus Slagle
			my ($no,$junk,$realname) =split(/:/,$serverline);
			my ($server,$cmdnum,$me,$whoshort,@rest) = split(/\s+/,$junk);
			$dbh->do("update irc_user set realname=? where shortname=?",undef,$realname,$whoshort);
		}
		elsif ($cmd == 433)
		{
			#:emancipator.whapps.com 433 * cinci_pm_bot_0 :Nickname already in use
                        $iter++;
                        die("nick dupe, retry");
                }
		else
		{
			print "unimpemented server cmd: ";
			print $serverline . "\n";
			return;
		}
	}

	return if (!$cmd);

	# ok, its a user!
        my ($whoshort, $wholong) = split(/!/, $who, 2);
        my $dbh = &get_dbh;
        my $userref = $dbh->selectrow_hashref("select * from irc_user where shortname=?",undef,$whoshort);

        if (!$userref->{id})
        {
		print $sock "WHOIS $whoshort\r\n";
                $dbh->do("insert into irc_user (shortname,longname) values (?,?)",undef,$whoshort,$wholong);
	        $userref = $dbh->selectrow_hashref("select * from irc_user where shortname=?",undef,$whoshort);
	}

	#ok, we have all of the details, lets log this thing
	eval {
		if ($cmd ne 'PING')
		{
			my $msg = $args;
			if ($cmd eq 'PRIVMSG')
			{
				my $cr;
				($cr,$msg) = split(/:/,$args,2);
			}
			my $chanref = $dbh->selectrow_hashref("select * from irc_channel where name=?",undef,$chan);
		
			if (!$chanref->{id})
			{
				$dbh->do("insert into irc_channel (name) values (?)",undef,$chan);
				$chanref = $dbh->selectrow_hashref("select * from irc_channel where name=?",undef,$chan);
			}

			if ($msg !~ /^bot lasts/)
			{
				$dbh->do("insert into irc_log (irc_channel_id,irc_user_id,irc_command,message,logged_at) values (?,?,?,?,now())",undef,
						$chanref->{id},$userref->{id},$cmd,$msg);
			}
		}

	};

        if ($cmd eq 'JOIN') 
	{
                print localtime(time) . " $whoshort ($wholong) has joined $args\n";
		if (($whoshort ne $me) && ($sson))
		{
			
	 		my @one = ("RRRRAAAAAARRRWWWRRR","Beware Coward!","Beware, I Live!","I am ... Sinistar","I Hunger!",                                                          
      					"I Hunger, Coward!","Run, Coward!","RUN RUN RUN!!!");
			my @s1 = shuffle(@one);
			print $sock "PRIVMSG $chan :$s1[0]\r\n";
			&local_echo($s1[0]);
		}
	}
	elsif ($cmd eq 'KICK')
	{
		# no
		my ($whoshort, $wholong) = split(/!/, $who, 2);
		my ($lchan, $the_kicked, $message) = split(/\s+/, $args, 3);
                print localtime(time) ." $whoshort ($wholong) has kicked $args\n";
		if ($the_kicked eq $me)
		{
			# no you didnt
		        print $sock "JOIN $lchan\r\n";
		}
		
	}
        elsif ($cmd eq 'PART') 
	{
                my ($whoshort, $wholong) = split(/!/, $who, 2);
                print localtime(time) . " $whoshort ($wholong) has left $args\n";
                ($args, undef) = split(/ /,$args, 2) if $args =~ / /;
	} 
	elsif ($cmd eq 'PING') 
	{
                print $sock "PONG $args\n";
                print "*** PONG $args\n";
	}
        elsif ($cmd eq 'QUIT') 
	{
                my ($whoshort,$wholong) = split(/!/, $who, 2);
                chop $args if ($args =~ /\W$/);
                print localtime(time) . " Signoff $whoshort ($args)\n";
        } 
	elsif ($cmd eq 'PRIVMSG')
	{
                my ($whoshort, $wholong) = split(/!/, $who, 2);
                my ($lchan, $message) = split(/\:/, $args, 2);
		print localtime(time) . " $whoshort: $message\n"; 

		# ok magic
		if (($message =~ /^cinci_pm_bot/) || ($message =~ /^bot\s+/))
		{
			my $me_or_alias;
			($me_or_alias,$message) = split(/\s+/,$message,2);
			
			if (!$message)
			{
				print $sock "PRIVMSG $lchan :usage $me_or_alias <command>\r\n";
				print $sock "PRIVMSG $lchan :implemented weather, sales, fortune, lastseen, lastsaid, randomator, forecast\r\n";
			}
                        elsif ($message =~ /^randomator/)
                        {
my @ators = qw(abator abbreviator abdicator aberrator aberuncator ablator abnegator abominator abrogator accelerator accentuator acclamator accommodator accumulator acetylator activator actuator acupuncturator acutiator adjudicator administrator admirator adstipulator adulator adulterator advocator aerator agglomerator agglutinator aggravator aggregator agistator agitator alienator allegator alleviator alligator alliterator allocator alternator amalgamator ambulator ameliorator amplificator amputator animator annihilator annotator annunciator anticipator anticreator antioxygenator antivaccinator antivibrator apiator applicator appreciator approbator appropriator approximator arbitrator arborator archagitator archconspirator archdepredator archsacrificator argumentator arrogator articulator asphyxiator aspirator assassinator assecurator assentator assimilator associator attemperator attenuator attestator auscultator authenticator autocollimator autocrator autokrator autoregenerator autoxidator auxiliator averruncator aviator avigator barrator brachiator bronchodilator buccinator cachinnator calculator calibrator calorisator calumniator capitulator caprificator captivator carbonator carburator cardioaccelerator cardiodilator castigator castrator catalyzator caveator celebrator centuriator certificator chlorinator chronocrator cinerator circulator circumambulator circumaviator circumnavigator citator classificator coadjudicator coadjutator coadministrator coagitator coagulator coarbitrator coattestator coconsecrator coconspirator cocreator cocurator coemptionator coformulator cogitator cohobator colegislator collaborator collator collimator combinator commemorator commendator commentator comminator commiserator communicator commutator companator comparator compensator compilator compotator compurgator concatenator concentrator conciliator concionator condensator confabulator confederator confiscator conflagrator conformator confutator congratulator congregator conjugator conjurator consecrator conservator considerator consignificator consolidator conspirator consummator contaminator contemplator continuator convocator corporator corroborator corrugator cosenator costipulator cotranslator counterorator creator cremator criminator cultivator cunctator cuneator curator deaerator dearsenicator debellator decapitator decarbonator decator decelerator decimator declarator decollator deconcentrator decorator decorticator dedicator defalcator defecator deflagrator deflator deflocculator defoliator degerminator dehydrator dejerator delator delegator deliberator delineator demarcator demodulator demonstrator denigrator denitrator denitrificator denominator denunciator deoxidator dephlegmator depilator depopulator deprecator depreciator depredator depurator deputator derogator desiccator designator deteriorator determinator detonator detoxicator devastator deviator devirginator dialyzator dictator differentiator digladiator dilapidator dilatator dilator disarticulator disceptator discriminator disintegrator dislocator dismembrator dispensator dispergator disputator disseminator dissertator dissimulator dissipator divaricator divinator domesticator dominator donator duplicator edificator educator edulcorator ejaculator elaborator elator elevator eliminator elucidator elutriator emanator emancipator emasculator emendator emigrator emulator enervator enucleator enumerator enunciator epitomator equator equilibrator equivocator eradicator Escalator escalator escheator estimator estivator evacuator evaporator evocator exaggerator examinator excavator excitator excogitator excommunicator excoriator excruciator excusator execrator exemplificator exhilarator exhortator exhumator exonerator expatiator expectorator experimentator expiator expilator expirator expiscator explanator explicator explorator expostulator expropriator expurgator exsiccator extenuator exterminator extirpator extrapolator fabricator facilitator falsificator fascinator fecundator federator felicitator filator fixator flagellator flocculator formulator fornicator fractionator fulgurator fulminator fumigator funambulator fustigator gator generator germinator gesticulator gladiator glossator graduator grammatolator granulator gubernator gyrator habilitator hallucinator hereticator hibernator hortator hospitator humiliator hydrator hydrogenator hyperpredator hypoeliminator hypothecator illuminator illustrator imaginator imitator immigrator immolator impanator imperator impermeator impersonator impetrator implorator importunator imprecator impregnator impropriator improvisator inaugurator incantator incarcerator incinerator inclinator incorporator incriminator incrustator incubator inculcator indagator indemnificator indicator individuator indoctrinator infatuator inhalator initiator innovator inoculator insinuator inspirator inspissator instaurator instigator instillator insufflator insulator integrator intercommunicator intermediator interpellator interpolator interrogator intimidator intonator intoxicator intubator inundator invalidator investigator invigilator invigorator invocator irradiator irrigator irritator jaculator jejunator joculator judicator jurator justificator kosmokrator lachrymator lapidator laudator legator legislator levator levigator levitator liberator ligator liquidator literator litigator lixiviator locator lubricator lucubrator luminator machinator magnetogenerator maladministrator malaxator maltreator mandator manipulator masticator masturbator matriculator mediator medicator meditator meliorator Mercator methylator micromanipulator migrator miniator ministrator miscalculator miscegenator miscreator mitigator moderator modificator modulator monochromator monstrator multiplicator multivibrator murmurator mutilator mystificator narrator natator navigator Necator negator negotiator nitrator nivellator nomenclator nominator nonagglutinator nonconspirator nonvibrator notator novator nucleator nugator nullificator numerator obfuscator objurgator obligator obliterator obtruncator obturator obviator odorator officiator operator opinator orator orchestrator ordinator orientator originator oscillator oxidator oxygenator oxygenerator ozonator pacificator palliator Pantocrator participator peculator pedipulator penetrator perambulator percolator peregrinator perfectionator perforator perlustrator permeator permutator perorator perpetrator perpetuator perscrutator personator personificator perturbator phrator piscator plicator pollinator populator postillator postulator potator preadministrator precipitator preconspirator predator predestinator predicator prediscriminator predominator prefabricator prefator pregustator preinvestigator prejudicator premeditator preoperator preparator preseparator presignificator prestidigitator prestigiator prevaricator probator proclamator procrastinator procreator procurator prognosticator promulgator pronator pronunciator propagator propitiator propugnator prorogator prostrator protestator provocator pulsator pulverizator punctator punctuator purificator pylorodilator quadruplator qualificator radiator radiolocator ratiocinator recapitulator reciprocator reconciliator recreator recriminator rectificator recuperator recusator redintegrator refrigerator regenerator registrator regrator regulator rehypothecator reinstator rejuvenator relator relevator relocator remonstrator remunerator renovator renunciator reprobator repudiator resonator respirator restorator resuscitator retaliator revelator reverberator rotator rubiator rubricator ruinator ruminator Russificator rusticator sacrificator salivator Saltator saltator saturator scarificator scintillator scrutator sectator segregator senator separator sequestrator sibilator signator significator simplificator simulator somnambulator sophisticator spectator spectrocomparator speculator spoliator stabilizator stannator stator stereocomparator sternutator stimulator stipulator stridulator strigilator subadministrator subconservator subcurator subescheator subjugator sublimator substantiator substrator sulfonator sulfurator sulphonator sulphurator supercommentator supererogator superseminator supinator supplicator sustentator syncopator syndicator tabulator taxator temporator teretipronator tergiversator terminator testator testificator thermogenerator thermoregulator titillator titivator tolerator totalizator tractator transformator transilluminator translator transliterator transmigrator treator triangulator triturator triumphator truncator tubulator turboalternator turbogenerator turboventilator underescheator undermediator unificator urinator vaccinator vacillator valuator variator variegator vasodilator vaticinator venator venerator ventilator versificator viator vibrator vindicator vinificator violator visitator vitiator vituperator vivificator vociferator zelator);

                            my @rd = shuffle(@ators);

                            print $sock "PRIVMSG $lchan :Random beer name: " . ucfirst(lc($rd[0])) . "\r\n";   
                            &local_echo("Random beer name: " . ucfirst(lc($rd[0])));  
                        }
			elsif ($message =~ /^sales/)
			{
				my @one = qw(aggregate architect benchmark brand cultivate deliver deploy disintermediate drive e-enable embrace empower enable engage engineer enhance envisioneer evolve expedite exploit extend facilitate generate grow harness implement incentivize incubate innovate integrate iterate leverage matrix maximize mesh monetize morph optimize orchestrate productize recontextualize redefine reintermediate reinvent repurpose revolutionize scale seize strategize streamline syndicate synergize synthesize target transform transition unleash utilize visualize whiteboard);
				my @two = qw(B2B B2C back-end best-of-breed bleeding-edge bricks-and-clicks clicks-and-mortar collaborative compelling cross-platform cross-media customized cutting-edge distributed dot-com dynamic e-business efficient end-to-end enterprise extensible frictionless front-end global granular holistic impactful innovative integrated interactive intuitive killer leading-edge magnetic mission-critical next-generation one-to-one open-source out-of-the-box plug-and-play proactive real-time revolutionary rich robust scalable seamless sexy sticky strategic synergistic transparent turn-key ubiquitous user-centric value-added vertical viral virtual visionary web-enabled wireless world-class);

				my @three = qw(APIs action-items applications architectures bandwidth channels communities content convergence deliverables e-business APIs e-commerce e-markets e-services e-tailers experiences eyeballs functionalities infomediaries infrastructures initiatives interfaces markets methodologies APIs metrics mindshare models networks niches paradigms partnerships platforms APIs portals relationships ROI synergies web-readiness schemas solutions supply-chains systems APIs technologies users vortals webservices);

				my @s1 = shuffle(@one);
				my @s2 = shuffle(@two);
				my @s3 = shuffle(@three);
				
				print $sock "PRIVMSG $lchan :Just say \"$s1[0] $s2[0] $s3[0]\".  It's a standard customization.\r\n";	
				&local_echo("Just say \"$s1[0] $s2[0] $s3[0]\".  It's a standard customization.");
			}
                        elsif ($message =~ /^sson/)
                        {
				$sson = 1;
                                print $sock "PRIVMSG $lchan :sson 1\r\n";
                        }
                        elsif ($message =~ /^ssoff/)
                        {
                                $sson = 0;
                                print $sock "PRIVMSG $lchan :sson 0\r\n";
                        }
                        elsif ($message =~ /^sinistar/)
                        {
                                my @one = ("RRRRAAAAAARRRWWWRRR","Beware Coward!","Beware, I Live!","I am ... Sinistar","I Hunger!",
					   "I Hunger, Coward!","Run, Coward!","RUN RUN RUN!!!");
                                my @s1 = shuffle(@one);
                                print $sock "PRIVMSG $lchan :$s1[0]\r\n";
				&local_echo($s1[0]);
                        }
			elsif ($message =~ /^weather/)
			{
				my $seesmetar;
				if ($message =~ /metar/)
				{
					$seesmetar = 1;
					$message =~ s/metar//g;
				}

				my @mparts = split(/\s+/,$message);
				my $station = $mparts[1] || 'kcvg';

				if ($message =~ /inside/)
				{
					my $dt = DateTime->now;
					my $tmp = `/Users/mslagle/Applications/HardwareMonitor.app/Contents/MacOS/hwmonitor -f 2>/dev/null| grep AMBIENT | cut -d':' -f2 | cut -d' ' -f2`;
					my $tmpc = `/Users/mslagle/Applications/HardwareMonitor.app/Contents/MacOS/hwmonitor 2>/dev/null| grep AMBIENT | cut -d':' -f2 | cut -d' ' -f2`;
					$tmp =~ s/[\r\n]//g;
					$tmpc =~ s/[\r\n]//g;
					my $metar;
					if ($seesmetar)
					{
						$metar = '(KCZ0 ' . sprintf('%02s%02s%02s',$dt->day,$dt->hour,$dt->minute) . 'Z VRB001KT 10SM OVC000CEL ' . sprintf('%02s',$tmpc) . '/00 AXXXX RMK A01)';
					}
                                        print $sock "PRIVMSG $lchan : Fair $tmp degrees - (no sensor) in $metar\r\n";
                                        &local_echo("Fair $tmp degrees - (no sensor) in $metar");					
				}
				else
				{
					my $w = Geo::WeatherNWS->new();
					$w->setservername('tgftp.nws.noaa.gov');
					$w->setusername('anonymous');
					$w->setpassword('marc.slagle@online-rewards.com');
					$w->setdirectory("/data/observations/metar/stations");
					$w->getreport($station);
					my $speed;
					if ($w->{windspeedmph} > 0)
					{
					        $speed = $w->{windspeedmph} . "mph";
					}
					my $metar;
					if ($seesmetar)
					{
						$metar = '(' . $w->{obs} . ')';
					}

                                        print $sock "PRIVMSG $lchan :$w->{conditionstext} $w->{temperature_f} degrees - $w->{pressure_inhg} in $metar\r\n";
					&local_echo("$w->{conditionstext} $w->{temperature_f} degrees - $w->{pressure_inhg} in $metar");
				}
			}
                        elsif ($message =~ /^fortune/)
                        {
			      	my @ret = `/opt/local/bin/fortune -s | tr '\n' ' '`;
		      		foreach my $line (@ret)
	      			{
					$line =~ s/\s+/ /g;
      					print $sock "PRIVMSG $lchan :$line\r\n";
					&local_echo($line);
				}
                        }
                        elsif ($message =~ /^forecast/)
                        {
                            eval {
                                my $fn = './cincinnati.json';
                                &lwp_fetch_data($fn);
                                my $fcon = slurp($fn);
                                my $json = from_json($fcon);

                                my $fc_data = $json->{forecast}->{simpleforecast}->{forecastday};
                                my (@r1,@r2,@r3);
                                push(@r1,' ');
                                push(@r2,'Conditions');
                                push(@r3,'Temp H/L');

                                my $utf_map = { chanceflurries => " \x{2603}  ",
                                                chancerain => " \x{2602}  ",
                                                chancesleet => " \x{2602}  ",
                                                chancesnow => " \x{2603}  ",
                                                chancetstorms => "\x{263c}/\x{2608}  ",
                                                clear => " \x{263c}  ", # '  ☼  ',
                                                cloudy => " \x{2601}  ",
                                                flurries => " \x{2603}  ",
                                                fog => ' Fog ',
                                                hazy => 'Haze ',
                                                mostlycloudy => "\x{263c}/\x{2601} ",  
                                                mostlysunny => "\x{263c}/\x{2601} ",  
                                                partlycloudy => "\x{263c}/\x{2601} ",  
                                                partlysunny => "\x{263c}/\x{2601} ",  
                                                sleet => " \x{2602}  ",
                                                rain => " \x{2602}  ",
                                                sleet => " \x{2602}  ",
                                                snow => " \x{2603}  ",
                                                sunny => " \x{263c}  ", #'  ☼  ',
                                                tstorms => " \x{2608}  ", };

                                foreach my $d (@$fc_data)
                                {
                                    push (@r1,'  ' . $d->{date}->{weekday_short} . ' ');
                                    if (my $ic = $utf_map->{$d->{icon}})
                                    {
                                        push (@r2,' '.$ic);
                                    }
                                    else
                                    {
                                        push (@r2,$d->{skyicon});
                                    }
                                    push (@r3,$d->{high}->{fahrenheit} . '/' . $d->{low}->{fahrenheit});
                                }

#                                print $sock "PRIVMSG $lchan :" . sprintf("%12s\t%8s\t%8s %8s %8s\r\n",@r1);
 #                               print $sock "PRIVMSG $lchan :" . sprintf("%12s\t%7s\t%7s %7s %7s\r\n",@r2);
  #                              print $sock "PRIVMSG $lchan :" . sprintf("%12s\t%8s\t%8s %8s %8s\r\n",@r3);

                                print $sock "PRIVMSG $lchan :" . pack("A12 A8 A8 A8 A8",$r1[0],$r1[1],$r1[2],$r1[3],$r1[4]) . "\r\n";
                                print $sock "PRIVMSG $lchan :" . pack("A12 A7 A7 A7 A7",$r2[0],$r2[1],$r2[2],$r2[3],' '.$r2[4]) . "\r\n";
                                print $sock "PRIVMSG $lchan :" . pack("A12 A8 A8 A8 A8",$r3[0],$r3[1],$r3[2],$r3[3],$r3[4]) . "\r\n";
                            };

                            if ($@)
                            {
                                warn $@;
                                print $sock "PRIVMSG $lchan :I can't get the data right now\r\n";
                            }
                        }
			elsif ($message =~ /^lastseen/)
			{
				my ($cmd,$user,$other) = split(/\s+/,$message,3);
				if ($user)
				{
					eval {
						my $dbh = &get_dbh;
						my $userref = $dbh->selectrow_hashref("select * from irclogs.irc_user where shortname=?",undef,$user);
						my $lastseen = $dbh->selectrow_hashref("select il.logged_at,ic.name from irclogs.irc_log il 
												inner join irclogs.irc_channel ic on (il.irc_channel_id=ic.id) 
												where irc_user_id=? order by logged_at desc limit 1",undef,$userref->{id});
						if ($lastseen->{logged_at})
						{
							print $sock "PRIVMSG $lchan :last saw $user at $lastseen->{logged_at} on $lastseen->{name}\r\n";
						}
						else
						{
							print $sock "PRIVMSG $lchan :\caACTION has never seen $user before\ca\n";
						}
					};
					if ($@)
					{
						print $sock "PRIVMSG $lchan :sorry: $@\r\n";
					}
				}
				else
				{
					print $sock "PRIVMSG $lchan :usage: lastseen nick\r\n";
				}
			}
                        elsif ($message =~ /^lastsaid/)
                        {
                                my ($cmd,$user,$other) = split(/\s+/,$message,3);
				if ($user)
				{
                                	eval {
                                	        my $dbh = &get_dbh;
                                	        my $userref = $dbh->selectrow_hashref("select * from irclogs.irc_user where shortname=?",undef,$user);
						my $chanref = $dbh->selectrow_hashref("select * from irclogs.irc_channel where name=?",undef,$lchan);
                                	        my $lastsaid = $dbh->selectrow_hashref("select * from irclogs.irc_log il 
												where irc_user_id=? and irc_channel_id=? and irc_command='PRIVMSG' 
												order by logged_at desc limit 1",undef,$userref->{id},$chanref->{id});
                                	        if ($lastsaid->{logged_at})
                                	        {
                                	                print $sock "PRIVMSG $lchan :$lastsaid->{logged_at} $user: $lastsaid->{message}\r\n";
                                	        }
                                	        else
                                	        {
                                	                print $sock "PRIVMSG $lchan :\caACTION has never seen $user say anything on $chanref->{name} before\ca\n";
                                	        }
                                	};
                                	if ($@)
                                	{
                                	        print $sock "PRIVMSG $lchan :sorry: $@\r\n";
                                	}                                                                                                                                                             
                                }
                                else
                                {
                                        print $sock "PRIVMSG $lchan :usage: lastsaid nick\r\n";
                                }
                        }

			else
			{
				$message =~ s/[\r\n]//g;
				if ($message =~ /\?$/)
				{
					my $val = 'http://lmgtfy.com/?q=' . uri_escape($message);
					print $sock "PRIVMSG $lchan :$whoshort: $val\n";
				}
				else
				{
                                    print $sock "PRIVMSG $lchan:Does not seem to be implemented\r\n";
				}
			}
		}
	}
	else 
	{
#:emancipator.whapps.com 433 * cinci_pm_bot_0 :Nickname already in use
		my @parts = split(/\s+/,$serverline);
                #print "*$parts[1]* $serverline\n";
		if ($parts[1] == 433)
		{
			# nick in use
			$iter++;
			die("nick dupe, retry");
		}
        }
}

sub lwp_fetch_data
{
    my $wd_file = shift;

    print "testing $wd_file\n";
    if (-f $wd_file)
    {
        my @statinfo = stat($wd_file);
        my $age8 = ($statinfo[8] - time()) * -1;
        my $age = ($statinfo[9] - time()) * -1;
        my $age10 = ($statinfo[10] - time()) * -1;
        print $age . " seconds\n";
        if ($age < 3600)
        {
            return;
        }
    }
    
    print "$wd_file isnt there/is too old\n";

    # ok to get a new file, this is an hour old
    my $ua = LWP::UserAgent->new();
    my $response = $ua->get('http://api.wunderground.com/api/fa4a3adf03db95fc/forecast/q/OH/Cincinnati.json');
    if ($response->is_success)
    {
        open(JSON,"> $wd_file");
        print $response->content;
        print JSON $response->content;
        close(JSON);
    }
    else
    {
        print Dumper($response);
        # must have busted... touch file to keep from sploding my key
        #system("touch $wd_file");
    }

    return;
}
