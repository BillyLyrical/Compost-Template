package Compost::Template::Misc;

use File::Spec;

our $VERSION = '0.1.0';

# -----------------------------------------
# some utilty subs ripped from CGI::Minimal;

sub url_encode {
#        my $self = shift;
        my ($s)=@_;
        return '' if (! defined ($s));
        $s=~s/([^-_.a-zA-Z0-9])/"\%".unpack("H2",$1)/egs;
        $s;
}

sub htmlize {
#        my $self = shift;
 
        my ($s)=@_;
        return ('') if (! defined($s));
        $s =~ s/\&/\&amp;/gs;
        $s =~ s/>/\&gt;/gs;
        $s =~ s/</\&lt;/gs;
        $s =~ s/"/\&quot;/gs;
        $s;
}


sub dehtmlize {
#        my $self = shift;

        my($s)=@_;;

        return ('') if (! defined($s));

        $s=~s/\&gt;/>/gs;
        $s=~s/\&lt;/</gs;
        $s=~s/\&quot;/\"/gs;
        $s=~s/\&amp;/\&/gs;

        return $s;
}

# -----------------------------------------
# taken from Compost::File 
# thanks to Benjamin Franz
# FIXME split into safe_path & safe_file

sub safe_file {
        my $file = shift;

        die "No filename passed?"
         unless ( defined $file and $file ne '' );

        my ( $volume, $directory, $filename ) = File::Spec->splitpath( $file );
        my @directory_elements                = File::Spec->splitdir( $directory );
        my @filtered_directory_elements       = File::Spec->no_upwards( @directory_elements );
        if ( $#filtered_directory_elements != $#directory_elements ) {
                die "Unsafe filename '$file' contains unallowed characters";
        }

        my @untainted_directory_elements = ();
        foreach my $dir_element ( @filtered_directory_elements ) {
                next if ( $dir_element eq '' );
                if ( $dir_element =~  m/^([-_a-zA-Z0-9.]{1,127})$/s ) {
                        push @untainted_directory_elements, $1;
                } else {
                        my $elements = join ' : ', @filtered_directory_elements;
                        die "Unsafe filename '$file' contains unallowed characters "
                         . "in path element $dir_element '$elements'";
                }
        }

        # Ok. This should be the directory we want.
        my $partial_path = File::Spec->catdir( @untainted_directory_elements );

        # Match 'good stuff'
        my ( $safe_filename ) = $filename =~ m/^([-_a-zA-Z0-9.]{1,127})$/s;
        unless ( defined $safe_filename ) {
                die "Unsafe filename '$file' contains unallowed characters";
        }

        # Return the final path to the file
        my $safe_file = File::Spec->catfile( File::Spec->rootdir(), $partial_path, $safe_filename );

        return $safe_file;
}

#thankyouverymuchgoodnight
1;


