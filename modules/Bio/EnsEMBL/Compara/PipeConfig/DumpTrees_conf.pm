=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016] EMBL-European Bioinformatics Institute

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


=pod 

=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::DumpTrees_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::DumpTrees_conf -password <your_password> -member_type protein

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::DumpTrees_conf -password <your_password> -member_type ncrna

=head1 DESCRIPTION  

    A pipeline to dump either protein_trees or ncrna_trees.

    In rel.60 protein_trees took 2h20m to dump.

    In rel.63 protein_trees took 51m to dump.
    In rel.63 ncrna_trees   took 06m to dump.

=head1 CONTACT

Please email comments or questions to the public Ensembl
developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

Questions may also be sent to the Ensembl help desk at
<http://www.ensembl.org/Help/Contact>.

=cut

package Bio::EnsEMBL::Compara::PipeConfig::DumpTrees_conf;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.4;
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;           # Allow this particular config to use conditional dataflow

use base ('Bio::EnsEMBL::Hive::PipeConfig::EnsemblGeneric_conf');   # we don't need Compara tables in this particular case

=head2 default_options

    Description : Implements default_options() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that is used to initialize default options.

=cut

sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },               # inherit other stuff from the base class

        ## Commented out to make sure people define it on the command line
        # either 'protein' or 'ncrna'
        #'member_type'       => 'protein',
        # either 'default' or 'murinae'
        #'clusterset_id'     => 'default',

        'pipeline_name'     => $self->o('member_type').'_'.$self->o('clusterset_id').'_'.$self->o('rel_with_suffix').'_dumps', # name used by the beekeeper to prefix job names on the farm

        # Standard registry file
        'production_registry' => "--reg_conf ".$self->o('ensembl_cvs_root_dir')."/ensembl-compara/scripts/pipeline/production_reg_conf.pl",
        'rel_db'        => 'compara_curr',

        'capacity'    => 100,                                                       # how many trees can be dumped in parallel
        'batch_size'  => 25,                                                        # how may trees' dumping jobs can be batched together

        'dump_script' => $self->o('ensembl_cvs_root_dir').'/ensembl-compara/scripts/dumps/dumpTreeMSA_id.pl',           # script to dump 1 tree
        'readme_dir'  => $self->o('ensembl_cvs_root_dir').'/ensembl-compara/docs/ftp',                                  # where the template README files are
        'target_dir'  => '/lustre/scratch110/ensembl/'.$self->o('ENV', 'USER').'/'.$self->o('pipeline_name'),           # where the final dumps will be stored
        'work_dir'    => $self->o('target_dir').'/dump_hash',                                                           # where directory hash is created and maintained
    };
}

sub resource_classes {
    my ($self) = @_;
    return {
        %{$self->SUPER::resource_classes},  # inherit 'default' from the parent class

         'default'      => {'LSF' => [ '', $self->o('production_registry') ], 'LOCAL' => [ '', $self->o('production_registry') ]  },
         '1Gb_job'      => {'LSF' => [ '-C0 -M1000  -R"select[mem>1000]  rusage[mem=1000]"', $self->o('production_registry') ], 'LOCAL' => [ '', $self->o('production_registry') ] },
         '2Gb_job'      => {'LSF' => [ '-C0 -M2000  -R"select[mem>2000]  rusage[mem=2000]"', $self->o('production_registry') ], 'LOCAL' => [ '', $self->o('production_registry') ] },
         '4Gb_job'      => {'LSF' => [ '-C0 -M4000  -R"select[mem>4000]  rusage[mem=4000]"', $self->o('production_registry') ], 'LOCAL' => [ '', $self->o('production_registry') ] },
         '10Gb_job'      => {'LSF' => [ '-C0 -M10000  -R"select[mem>10000]  rusage[mem=10000]"', $self->o('production_registry') ], 'LOCAL' => [ '', $self->o('production_registry') ] },
    };
}

sub pipeline_wide_parameters {  # these parameter values are visible to all analyses, can be overridden by parameters{} and input_id{}
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class

        'target_dir'    => $self->o('target_dir'),
        'work_dir'      => $self->o('work_dir'),

        'member_type'   => $self->o('member_type'),
        'clusterset_id' => $self->o('clusterset_id'),

        'basename'      => '#member_type#_#clusterset_id#',
        'name_root'     => 'Compara.'.$self->o('rel_with_suffix').'.#basename#',

        'rel_db'        => $self->o('rel_db'),
    };
}


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines seven analyses:

                    * 'create_dump_jobs'   generates a list of tree_ids to be dumped

                    * 'dump_a_tree'         dumps one tree in multiple formats

                    * 'generate_collations' generates five jobs that will be merging the hashed single trees

                    * 'collate_dumps'       actually merge/collate single trees into long dumps

                    * 'remove_hash'         remove the temporary hash of directories

                    * 'archive_long_files'  zip the long dumps

                    * 'md5sum'              compute md5sum for compressed files


=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [

        {   -logic_name => 'pipeline_start',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                'readme_dir'    => $self->o('readme_dir'),
                'cmd'           => join('; ',
                                    'mkdir -p #work_dir# #target_dir#/xml #target_dir#/emf',
                                    'cp -af #readme_dir#/gene_trees.emf_dumps.txt #target_dir#/emf/README.#basename#_trees.emf_dumps.txt',
                                    'cp -af #readme_dir#/gene_trees.xml_dumps.txt #target_dir#/xml/README.#basename#_trees.xml_dumps.txt',
                                   ),
            },
            -input_ids  => [ {} ],
            -flow_into  => {
                '1->A' => [ 'create_dump_jobs' ],
                'A->1' => [ 'md5sum' ],
            },
        },

          { -logic_name => 'dump_for_uniprot',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::DbCmd',
            -parameters => {
                'db_conn'       => '#rel_db#',
                'output_file'   => sprintf('#target_dir#/ensembl.GeneTree_content.#clusterset_id#.e%s.txt', $self->o('ensembl_release')),
                'append'        => [qw(-N -q)],
                'input_query'   => sprintf q|
                    SELECT 
                        gtr.stable_id AS GeneTreeStableID, 
                        pm.stable_id AS EnsPeptideStableID,
                        gm.stable_id AS EnsGeneStableID,
                        IF(m.seq_member_id = pm.seq_member_id, 'Y', 'N') as Canonical
                    FROM
                        gene_tree_root gtr
                        JOIN gene_tree_node gtn ON (gtn.root_id = gtr.root_id)
                        JOIN seq_member m on (gtn.seq_member_id = m.seq_member_id)
                        JOIN gene_member gm on (m.gene_member_id = gm.gene_member_id)
                        JOIN seq_member pm on (gm.gene_member_id = pm.gene_member_id)
                    WHERE
                        gtr.member_type = 'protein'
                        AND gtr.stable_id IS NOT NULL
                        AND gtr.clusterset_id = '#clusterset_id#'
                |,
            },
            -flow_into => {
                1 => { 'archive_long_files' => { 'full_name' => '#output_file#' } },
            },
          },

        {   -logic_name => 'dump_all_homologies_orthoxml',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::DumpAllHomologiesOrthoXML',
            -parameters => {
                'compara_db'            => '#rel_db#',
                'protein_tree_range'    => '0-99999999',
                'ncrna_tree_range'      => '100000000-199999999',
                'idrange'               => '#expr( $self->param(#member_type#."_tree_range") )expr#',
            },
            -flow_into => {
                1 => {
                    'archive_long_files' => { 'full_name' => '#file#', },
                    }
            },
        },

        {   -logic_name => 'dump_all_trees_orthoxml',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::DumpAllTreesOrthoXML',
            -parameters => {
                'compara_db'            => '#rel_db#',
                'tree_type'             => 'tree',
            },
            -rc_name => '1Gb_job',
            -flow_into => {
                1 => { 'archive_long_files' => { 'full_name' => '#file#' } },
               -1 => [ 'dump_all_trees_orthoxml_himem' ],  # MEMLIMIT
            },
        },

        {   -logic_name => 'dump_all_trees_orthoxml_himem',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::DumpAllTreesOrthoXML',
            -parameters => {
                'compara_db'            => '#rel_db#',
                'tree_type'             => 'tree',
            },
            -rc_name => '1Gb_job',
            -flow_into => {
                1 => {
                    'archive_long_files' => { 'full_name' => '#file#' },
                    }
            },
        },

          { -logic_name => 'dump_all_homologies_tsv',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::DbCmd',
            -parameters => {
                'db_conn'       => '#rel_db#',
                'output_file'   => '#target_dir#/#name_root#.homologies.tsv',
                'append'        => [qw(-q)],
                'min_hom_id'    => '#expr(#member_type# eq "protein" ? 0 : 100000000)expr#',
                'max_hom_id'    => '#expr(#min_hom_id# + 99999999)expr#',
                'input_query'   => sprintf q|
                    SELECT
                        gm1.stable_id AS gene_stable_id,
                        sm1.stable_id AS protein_stable_id,
                        gdb1.name AS species,
                        hm1.perc_id AS identity,
                        h.description AS homology_type,
                        gm2.stable_id AS homology_gene_stable_id,
                        sm2.stable_id AS homology_protein_stable_id,
                        gdb2.name AS homology_species,
                        hm2.perc_id AS homology_identity
                    FROM
                        homology h
                        JOIN (homology_member hm1 JOIN gene_member gm1 USING (gene_member_id) JOIN genome_db gdb1 USING (genome_db_id) JOIN seq_member sm1 USING (seq_member_id)) USING (homology_id)
                        JOIN (homology_member hm2 JOIN gene_member gm2 USING (gene_member_id) JOIN genome_db gdb2 USING (genome_db_id) JOIN seq_member sm2 USING (seq_member_id)) USING (homology_id)
                    WHERE
                        homology_id BETWEEN #min_hom_id# AND #max_hom_id#
                |,
            },
            -flow_into => {
                1 => { 'archive_long_files' => { 'full_name' => '#output_file#' } },
            },
          },

        {   -logic_name => 'create_dump_jobs',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'db_conn'               => '#rel_db#',
                'inputquery'            => 'SELECT root_id AS tree_id FROM gene_tree_root WHERE tree_type = "tree" AND clusterset_id = "#clusterset_id#" AND member_type = "#member_type#"',
            },
            -flow_into => {
                'A->1' => 'generate_collations',
                '2->A' => { 'dump_a_tree'  => { 'tree_id' => '#tree_id#', 'hash_dir' => '#expr(dir_revhash(#tree_id#))expr#' } },
                1 => [
                    WHEN('#member_type# eq "protein"' => 'dump_for_uniprot'),
                    {
                        'dump_all_homologies_tsv' => undef,
                        'dump_all_trees_orthoxml' => { 'file' => '#target_dir#/xml/#name_root#.alltrees.orthoxml.xml', },
                        'dump_all_homologies_orthoxml' => [
                            {'file' => '#target_dir#/xml/#name_root#.allhomologies.orthoxml.xml'},
                            {'file' => '#target_dir#/xml/#name_root#.allhomologies_strict.orthoxml.xml', 'high_confidence' => 1},
                        ],
                    }
                ],
            },
        },

        {   -logic_name    => 'dump_a_tree',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters    => {
                'production_registry' => $self->o('production_registry'),
                'dump_script'       => $self->o('dump_script'),
                'tree_args'         => '-nh 1 -a 1 -nhx 1 -f 1 -fc 1 -oxml 1 -pxml 1 -cafe 1',
                'cmd'               => '#dump_script# #production_registry# --reg_alias #rel_db# --dirpath #work_dir#/#hash_dir# --tree_id #tree_id# #tree_args#',
            },
            -hive_capacity => $self->o('capacity'),       # allow several workers to perform identical tasks in parallel
            -batch_size    => $self->o('batch_size'),
            -rc_name       => '2Gb_job',
        },

        {   -logic_name => 'generate_collations',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'protein_tree_list' => [ 'aln.emf', 'nh.emf', 'nhx.emf', 'aa.fasta', 'cds.fasta' ],
                'ncrna_tree_list'   => [ 'aln.emf', 'nh.emf', 'nhx.emf', 'nt.fasta' ],
                'inputlist'         => '#expr( $self->param(#member_type#."_tree_list") )expr#',
                'column_names'      => [ 'extension' ],
            },
            -flow_into => {
                '1->A' => [ 'generate_tarjobs' ],
                '2->A' => { 'collate_dumps'  => { 'extension' => '#extension#', 'dump_file_name' => '#name_root#.#extension#'} },
                'A->1' => 'remove_hash',
            },
        },

        {   -logic_name    => 'collate_dumps',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters    => {
                'cmd'           => 'find #work_dir# -name "tree.*.#extension#" | sort -t . -k2 -n | xargs cat > #target_dir#/emf/#dump_file_name#',
            },
            -hive_capacity => 2,
            -flow_into => {
                1 => { 'archive_long_files' => { 'full_name' => '#target_dir#/emf/#dump_file_name#' } },
            },
        },

        {   -logic_name => 'generate_tarjobs',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'protein_tree_list' => [ 'orthoxml.xml', 'phyloxml.xml', 'cafe_phyloxml.xml' ],
                'ncrna_tree_list'   => [ 'orthoxml.xml', 'phyloxml.xml', 'cafe_phyloxml.xml' ],
                'inputlist'         => '#expr( $self->param(#member_type#."_tree_list") )expr#',
                'column_names'      => [ 'extension' ],
            },
            -flow_into => {
                2 => { 'tar_dumps'  => { 'extension' => '#extension#', 'dump_file_name' => '#name_root#.tree.#extension#'} },
            },
        },

        {   -logic_name => 'tar_dumps',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                'cmd'           => 'find #work_dir# -name "tree.*.#extension#" | sed "s:#work_dir#/*::" | sort -t . -k2 -n | tar cf #target_dir#/xml/#dump_file_name#.tar -C #work_dir# -T /dev/stdin --transform "s:^.*/:#member_type#:"',
            },
            -hive_capacity => 2,
            -flow_into => {
                1 => { 'archive_long_files' => { 'full_name' => '#target_dir#/xml/#dump_file_name#.tar' } },
            },
        },

        {   -logic_name => 'remove_hash',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                'cmd'         => 'rm -rf #work_dir#',
            },
        },

        {   -logic_name => 'archive_long_files',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                'cmd'         => 'gzip #full_name#',
            },
        },

        {   -logic_name => 'md5sum',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                'cmd' => 'cd #target_dir#/emf ; md5sum *.gz >MD5SUM.#basename#_trees; cd #target_dir#/xml ; md5sum *.gz >MD5SUM.#basename#_trees',
            },
        },

    ];
}

1;

