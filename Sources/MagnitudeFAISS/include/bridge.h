// CPU
#include "AutoTune_c.h"
#include "clone_index_c.h"
#include "Clustering_c.h"
#include "error_c.h"
#include "error_impl.h"
#include "faiss_c.h"
#include "Index_c.h"
#include "index_factory_c.h"
#include "index_io_c.h"
#include "IndexBinary_c.h"
#include "IndexFlat_c.h"
#include "IndexIVF_c.h"
#include "IndexIVFFlat_c.h"
#include "IndexLSH_c.h"
#include "IndexPreTransform_c.h"
#include "IndexReplicas_c.h"
#include "IndexScalarQuantizer_c.h"
#include "IndexShards_c.h"
#include "MetaIndexes_c.h"
#include "VectorTransform_c.h"

// Implementation
#include "impl/AuxIndexStructures_c.h"
// Utils
#include "utils/distances_c.h"

#include <Accelerate/Accelerate.h>
