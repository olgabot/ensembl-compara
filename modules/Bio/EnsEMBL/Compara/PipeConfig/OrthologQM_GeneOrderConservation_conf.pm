=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2019] EMBL-European Bioinformatics Institute

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


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::OrthologQM_GeneOrderConservation_conf;

=head1 DESCRIPTION

    if a default threshold is not given the pipeline will use the genetic distance between the pair species to choose between a threshold of 50 and 75 percent.
	http://www.ebi.ac.uk/seqdb/confluence/display/EnsCom/Quality+metrics+for+the+orthologs


Example initialization (to compute GOC on a single -orthology- MLSS)
        init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::OrthologQM_GeneOrderConservation_conf -goc_mlss_id <20620> -goc_threshold (optional) -pipeline_name <GConserve_trial> -host <host_server> [-goc_reuse_db <>] -compara_db <>

Alternatively, set goc_taxlevels instead of goc_mlss_id to work on multiple taxa

=cut


package Bio::EnsEMBL::Compara::PipeConfig::OrthologQM_GeneOrderConservation_conf;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.4;
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;  
use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');
use Bio::EnsEMBL::Compara::PipeConfig::Parts::GOC;

sub hive_meta_table {
    my ($self) = @_;
    return {
        %{$self->SUPER::hive_meta_table},       # here we inherit anything from the base class

        'hive_use_param_stack'  => 1,           # switch on the new param_stack mechanism
    };
}


sub default_options {
    my $self = shift;
    return {
            %{ $self->SUPER::default_options() },

        # mlss_id of the protein-trees. The pipeline will process all the orthologues found there
        'mlss_id'       => undef,
        # mlss_id of a specific pair of species
        'goc_mlss_id'   => undef, #'100021',

        # Vertebrates
        'goc_taxlevels' => ["Euteleostomi","Ciona"],
        # Plants
        #'goc_taxlevels' => ['solanum', 'fabids', 'Brassicaceae', 'Pooideae', 'Oryzoideae', 'Panicoideae'],
        'goc_reuse_db'  => undef,
        'calculate_goc_distribution'    => 1,
        'goc_threshold' => 50,

        # Capacities and batch-sizes
        'goc_capacity'          => 30,
        'goc_batch_size'        => 20,
        'goc_stats_capacity'    => 5,
    };
}

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class
        'mlss_id' => $self->o('mlss_id'),
        'goc_mlss_id' => $self->o('goc_mlss_id'),
        'compara_db' => $self->o('compara_db'),
        'goc_threshold'  => $self->o('goc_threshold'),
        'goc_reuse_db'     => $self->o('goc_reuse_db'),
	'calculate_goc_distribution'  => $self->o('calculate_goc_distribution'),
        'goc_capacity'   => $self->o('goc_capacity'),
    };
}


sub pipeline_analyses {
    my ($self) = @_;
    my $a = [
        @{ Bio::EnsEMBL::Compara::PipeConfig::Parts::GOC::pipeline_analyses_goc($self)  },
	];
    $a->[0]->{-input_ids} = [{}];
    return $a;
}

1;
