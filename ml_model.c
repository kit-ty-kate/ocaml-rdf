/* */


#include "ml_model.h"


Make_Val_final_pointer(librdf_model, Ignore, Ignore, 0)

ML_3 (librdf_new_model, Librdf_world_val, Librdf_storage_val, String_val, Val_option_librdf_model)
ML_1 (librdf_new_model_from_model, Librdf_model_val, Val_librdf_model)
ML_1 (librdf_free_model, Librdf_model_val, Unit)

ML_2 (librdf_model_add_statement, Librdf_model_val, Librdf_statement_val, Val_int)
ML_2 (librdf_model_find_statements, Librdf_model_val, Librdf_statement_val, Val_option_librdf_stream)
ML_2 (librdf_model_write, Librdf_model_val, Raptor_iostream_val, Val_int)