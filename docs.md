# Docs

## Instruction Set

Mini defines the following 76 instructions:

	set_rstack
	set_dstack	

	store
	store_byte
	load

	return
	branch_impl
	jump_impl
	crash

	literal_impl
	copy
	drop
	over
	swap


	eq_zero
	eq
	gt

	push
	pop

	not
	or
	add
	sub

	invoke
	
	exit_process
	get_std_handle
	write_file
	read_file
	get_last_error

	entry_name
	entry_is_immediate
	msg_too_long
	msg_not_found
	dictionary
	find

	string_copy
	string_eq

	number
	initialize
	banner

	init_io
	stdin_handle
	stdout_handle
	print
	input_buffer
	input_end_ptr
	input_buffer_size
	input_refill
	input_read_ptr
	input_update

	assert
	ones
	zeroes

	parser_next
	parser_move_string
	parser_ingest_word
	parser_allocate
	parser_word
	parser_usage
	parser_strip
	parser_buffer
	parser_buffer_size
	parser_write_ptr
	parser_spaces
	parser_nonspaces

	arena
	arena_top
	arena_size
	cell_align

	begin
	end
	assemble
	assemble_byte
	is_assembling

	ptr_get_proc_address
	ptr_get_module_handle
