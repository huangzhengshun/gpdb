CREATE TABLE test_hash (a int, b text);
INSERT INTO test_hash VALUES (1, 'one');
CREATE INDEX test_hash_a_idx ON test_hash USING hash (a);

\x

SELECT hash_page_type(get_raw_page('test_hash_a_idx', 0));
SELECT hash_page_type(get_raw_page('test_hash_a_idx', 1));
SELECT hash_page_type(get_raw_page('test_hash_a_idx', 2));
SELECT hash_page_type(get_raw_page('test_hash_a_idx', 3));
SELECT hash_page_type(get_raw_page('test_hash_a_idx', 4));
SELECT hash_page_type(get_raw_page('test_hash_a_idx', 5));
SELECT hash_page_type(get_raw_page('test_hash_a_idx', 6));


SELECT * FROM hash_bitmap_info('test_hash_a_idx', 0);
SELECT * FROM hash_bitmap_info('test_hash_a_idx', 1);
SELECT * FROM hash_bitmap_info('test_hash_a_idx', 2);
SELECT * FROM hash_bitmap_info('test_hash_a_idx', 3);
SELECT * FROM hash_bitmap_info('test_hash_a_idx', 4);
SELECT * FROM hash_bitmap_info('test_hash_a_idx', 5);



SELECT * FROM hash_metapage_info(get_raw_page('test_hash_a_idx', 0));
SELECT * FROM hash_metapage_info(get_raw_page('test_hash_a_idx', 1));
SELECT * FROM hash_metapage_info(get_raw_page('test_hash_a_idx', 2));
SELECT * FROM hash_metapage_info(get_raw_page('test_hash_a_idx', 3));
SELECT * FROM hash_metapage_info(get_raw_page('test_hash_a_idx', 4));
SELECT * FROM hash_metapage_info(get_raw_page('test_hash_a_idx', 5));


SELECT * FROM hash_page_stats(get_raw_page('test_hash_a_idx', 0));
SELECT * FROM hash_page_stats(get_raw_page('test_hash_a_idx', 1));
SELECT * FROM hash_page_stats(get_raw_page('test_hash_a_idx', 2));
SELECT * FROM hash_page_stats(get_raw_page('test_hash_a_idx', 3));
SELECT * FROM hash_page_stats(get_raw_page('test_hash_a_idx', 4));
SELECT * FROM hash_page_stats(get_raw_page('test_hash_a_idx', 5));


SELECT * FROM hash_page_items(get_raw_page('test_hash_a_idx', 0));
SELECT * FROM hash_page_items(get_raw_page('test_hash_a_idx', 1));
SELECT * FROM hash_page_items(get_raw_page('test_hash_a_idx', 2));
SELECT * FROM hash_page_items(get_raw_page('test_hash_a_idx', 3));
SELECT * FROM hash_page_items(get_raw_page('test_hash_a_idx', 4));
SELECT * FROM hash_page_items(get_raw_page('test_hash_a_idx', 5));


DROP TABLE test_hash;
