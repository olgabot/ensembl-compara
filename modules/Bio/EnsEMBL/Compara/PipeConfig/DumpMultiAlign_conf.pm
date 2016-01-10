=head1 LICENSE

Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=head1 SYNOPSIS

Initialise the pipeline on comparaY and dump the alignments found in the database msa_db_to_dump at comparaX:

  init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::DumpMultiAlign_conf --host comparaY --compara_db mysql://ensro@comparaX/msa_db_to_dump --export_dir where/the/dumps/will/be/

Dumps are created in a sub-directory of --export_dir, which defaults to scratch109

The pipeline can dump all the alignments it finds on a server, so you can do something like:

  init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::DumpMultiAlign_conf --host comparaY --compara_db mysql://ensro@ens-staging1/ensembl_compara_80 --reg_conf path/to/production_reg_conf.pl
  init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::DumpMultiAlign_conf --host comparaY --compara_db compara_prev --reg_conf path/to/production_reg_conf.pl --format maf --method_link_types EPO

Note that in this case, because the locator field is not set, you need to provide a registry file

Format can be "emf", "maf", or anything BioPerl can provide (the pipeline will fail in the latter case, so
come and talk to us). It also accepts "emf+maf" to generate both emf and maf files


Release 65

 epo 6 way: 3.4 hours
 epo 12 way: 2.7 hours
 mercator/pecan 19 way: 5.5 hours
 low coverage epo 35 way: 43 hours (1.8 days)

=cut

package Bio::EnsEMBL::Compara::PipeConfig::DumpMultiAlign_conf;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.4;
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;           # Allow this particular config to use conditional dataflow

use base ('Bio::EnsEMBL::Hive::PipeConfig::EnsemblGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


sub default_options {
    my ($self) = @_;
    return {
        %{$self->SUPER::default_options},   # inherit the generic ones

        # By default, the pipeline will follow the "locator" of each
        # genome_db. You only have to set reg_conf if the locators
        # are missing.
        'reg_conf' => '',

        # Compara reference to dump. Can be the "species" name (if loading the Registry via reg_conf)
        # or the url of the database itself
        # Intentionally left empty
        #'compara_db' => 'Multi',

        'export_dir'    => '/lustre/scratch109/ensembl/'.$ENV{'USER'}.'/dumps_'.$self->o('rel_with_suffix'),

        # Maximum number of blocks per file
        'split_size' => 200,

        # See DumpMultiAlign.pl
        #  0 for unmasked sequence (default)
        #  1 for soft-masked sequence
        #  2 for hard-masked sequence
        'masked_seq' => 1,

        # Usually "maf", "emf", or "emf+maf". BioPerl alignment formats are
        # accepted in principle, but a healthcheck would have to be implemented
        'format' => 'emf',

        # one of 'dir' (directory of compressed files), 'tar' (compressed tar archive of a directory of uncompressed files), or 'file' (single compressed file)
        'mode' => 'dir',
        # how the files will be split: either 'chromosome' or 'random'
        # In "random" mode, we don't care about the chromsome names and coordinate systems, we let createOtherJobs bin the alignment blocks into chunks
        'split_mode' => 'chromosome',

        'dump_program' => $self->o('ensembl_cvs_root_dir')."/ensembl-compara/scripts/dumps/DumpMultiAlign.pl",
        'emf2maf_program' => $self->o('ensembl_cvs_root_dir')."/ensembl-compara/scripts/dumps/emf2maf.pl",

        # Method link types of mlss_id to retrieve
        'method_link_types' => 'BLASTZ_NET:TRANSLATED_BLAT:TRANSLATED_BLAT_NET:LASTZ_NET:PECAN:EPO:EPO_LOW_COVERAGE',

        # Specific mlss_id to dump. Leave undef as the pipeline can detect
        # it automatically
        'mlss_id'   => undef,
    };
}


# Ensures species output parameter gets propagated implicitly
sub hive_meta_table {
    my ($self) = @_;

    return {
        %{$self->SUPER::hive_meta_table},
        'hive_use_param_stack'  => 1,
    };
}

sub pipeline_wide_parameters {
    my ($self) = @_;

    return {
        %{$self->SUPER::pipeline_wide_parameters},

        'dump_program'      => $self->o('dump_program'),
        'emf2maf_program'   => $self->o('emf2maf_program'),

        'dump_mode'     => $self->o('mode'),
        'split_mode'    => $self->o('split_mode'),
        'format'        => $self->o('format'),
        'split_size'    => $self->o('split_size'),
        'reg_conf'      => $self->o('reg_conf'),
        'compara_db'    => $self->o('compara_db'),
        'export_dir'    => $self->o('export_dir'),
        'masked_seq'    => $self->o('masked_seq'),

        output_dir      => '#export_dir#/#base_filename#',
        output_file_gen => '#output_dir#/#base_filename#.#region_name#.#format#',
        output_file     => '#output_dir#/#base_filename#.#region_name##filename_suffix#.#format#',
    };
}

sub resource_classes {
    my ($self) = @_;

    return {
        %{$self->SUPER::resource_classes},  # inherit 'default' from the parent class
        'crowd' => { 'LSF' => '-C0 -M2000 -R"select[mem>2000] rusage[mem=2000]"' },
        'default_with_reg_conf' => { 'LSF' => ['', '--reg_conf '.$self->o('reg_conf')], 'LOCAL' => ['', '--reg_conf '.$self->o('reg_conf')] },
        'crowd_with_reg_conf' => { 'LSF' => ['-C0 -M2000 -R"select[mem>2000] rusage[mem=2000]"', '--reg_conf '.$self->o('reg_conf')], 'LOCAL' => ['', '--reg_conf '.$self->o('reg_conf')] },
    };
}

sub pipeline_analyses {
    my ($self) = @_;
    return [

        {   -logic_name     => 'create_tracking_tables',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
            -parameters     => {
                'sql'    => [
                    #Store DumpMultiAlign other_gab genomic_align_block_ids
                    'CREATE TABLE other_gab (genomic_align_block_id bigint NOT NULL)',
                    #Store DumpMultiAlign healthcheck results
                    'CREATE TABLE healthcheck (filename VARCHAR(400) NOT NULL, expected INT NOT NULL, dumped INT NOT NULL)',
                ],
            },
            -input_ids     => [ {} ],
        },

        {   -logic_name    => 'MLSSJobFactory',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::MLSSJobFactory',
            -parameters    => {
                'method_link_types' => $self->o('method_link_types'),
            },
            -input_ids     => [
                {
                    'mlss_id'           => $self->o('mlss_id'),
                },
            ],
            -flow_into      => {
                '2' => [ 'count_blocks' ],
            },
            -rc_name => 'default_with_reg_conf',
        },

        {  -logic_name  => 'count_blocks',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'db_conn'       => '#compara_db#',
                'inputquery'    => 'SELECT COUNT(*) AS num_blocks FROM genomic_align_block WHERE method_link_species_set_id = #mlss_id#',
            },
            -flow_into  => {
                '2->A' => WHEN(
                    '(#dump_mode# ne "file") and (#split_mode# eq "random")' => { 'createOtherJobs' => {'do_all_blocks' => 1} },
                    '(#dump_mode# ne "file") and (#split_mode# eq "chromosome")' => [ 'initJobs' ],
                    '#dump_mode# eq "file"' => { 'dumpMultiAlign' => {'region_name' => 'all', 'filename_suffix' => '*', 'extra_args' => [], 'num_blocks' => '#num_blocks#'} },    # a job to dump all the blocks in 1 file
                ),
                'A->2' => WHEN(
                        '#run_emf2maf#' => [ 'move_maf_files' ],
                        ELSE 'md5sum'
                    ),
            },
            -wait_for   => 'create_tracking_tables',
            -rc_name    => 'default_with_reg_conf',
        },

        {  -logic_name  => 'initJobs',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::InitJobs',
            -flow_into => {
                2 => [ 'createChrJobs' ],
                3 => [ 'createSuperJobs' ],
                4 => [ 'createOtherJobs' ],
            },
            -rc_name => 'default_with_reg_conf',
        },
        # Generates DumpMultiAlign jobs from genomic_align_blocks on chromosomes (1 job per chromosome)
        {  -logic_name    => 'createChrJobs',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::CreateChrJobs',
            -flow_into => {
                2 => [ 'dumpMultiAlign' ]
            },
            -rc_name => 'default_with_reg_conf',
        },
        # Generates DumpMultiAlign jobs from genomic_align_blocks on supercontigs (1 job per coordinate-system)
        {  -logic_name    => 'createSuperJobs',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::CreateSuperJobs',
            -flow_into => {
                2 => [ 'dumpMultiAlign' ]
            },
            -rc_name => 'default_with_reg_conf',
        },
        # Generates DumpMultiAlign jobs from genomic_align_blocks that do not contain $species
        {  -logic_name    => 'createOtherJobs',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::CreateOtherJobs',
            -rc_name => 'crowd',
            -flow_into => {
                2 => [ 'dumpMultiAlign' ]
            },
            -rc_name => 'crowd_with_reg_conf',
        },
        {  -logic_name    => 'dumpMultiAlign',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::DumpMultiAlign',
            -analysis_capacity => 50,
            -rc_name => 'crowd',
            -flow_into => [ WHEN(
                '#run_emf2maf#' => [ 'emf2maf' ],
                '!#run_emf2maf# && (#dump_mode# ne "tar")' => [ 'compress' ],
            ) ],
        },
        {   -logic_name     => 'emf2maf',
            -module         => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::Emf2Maf',
            -analysis_capacity  => 5,
            -rc_name        => 'crowd',
            -flow_into => [
                WHEN( '#dump_mode# ne "tar"' => { 'compress' => [ undef, { 'format' => 'maf'} ] } ),
            ],
        },
        {   -logic_name     => 'compress',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters     => {
                'cmd'           => 'gzip -f -9 #output_file#',
            },
            -analysis_capacity => 1,
        },
        {   -logic_name     => 'md5sum',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters     => {
                'cmd'           => 'cd #output_dir#; md5sum *.#format#* > MD5SUM',
            },
            -flow_into      =>  [ 'readme' ],
        },
        {   -logic_name     => 'move_maf_files',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters     => {
                'cmd'           => 'mv #output_dir#/*.maf* #output_dir#_maf/'
            },
            -flow_into      => { 1 => { 'md5sum' => [undef, { 'format' => 'maf', 'base_filename' => '#base_filename#_maf'} ] } },
        },
        {   -logic_name    => 'readme',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::Readme',
            -parameters    => {
                'mode'  => '#dump_mode#',
                'readme_file' => '#output_dir#/README.#base_filename#',
            },
            -flow_into     => WHEN( '#dump_mode# eq "tar"' => [ 'targz' ] ),
            -rc_name => 'default_with_reg_conf',
        },
        {   -logic_name     => 'targz',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters     => {
                'cmd'           => 'cd #export_dir#; tar czf #base_filename#.tar.gz #base_filename#',
            },
        },
    ];
}

1;
