#include <openssl/rsa.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
int main(){
FILE *fileptr;
unsigned char *env;
long envlen;
unsigned char *sig;
long siglen;

fileptr = fopen("/boot/dm-verity.env", "rb");  // Open the file in binary mode
fseek(fileptr, 0, SEEK_END);          // Jump to the end of the file
envlen = ftell(fileptr);             // Get the current byte offset in the file
rewind(fileptr);                      // Jump back to the beginning of the file

env = (unsigned char *)malloc(envlen * sizeof(unsigned char)); // Enough memory for the file
fread(env, envlen, 1, fileptr); // Read in the entire file
fclose(fileptr); // Close the file

fileptr = fopen("/boot/dm-verity.env.sig", "rb");  // Open the file in binary mode
fseek(fileptr, 0, SEEK_END);          // Jump to the end of the file
siglen = ftell(fileptr);             // Get the current byte offset in the file
rewind(fileptr);                      // Jump back to the beginning of the file

sig = (unsigned char *)malloc(siglen * sizeof(unsigned char)); // Enough memory for the file
fread(sig, siglen, 1, fileptr); // Read in the entire file
fclose(fileptr); // Close the file

  EVP_MD_CTX *mdctx = NULL;
  if(!(mdctx = EVP_MD_CTX_create())) return 1;

  EVP_PKEY *pubkey =NULL;
FILE* pFile = fopen("/cert.pem","rb");
pubkey = PEM_read_PUBKEY(pFile,NULL,NULL,NULL);

    
  if(1 != EVP_DigestVerifyInit(mdctx, NULL, EVP_sha256(), NULL, pubkey)) return 2;
  
  /* Initialize `key` with a public key */
  if(1 != EVP_DigestVerifyUpdate(mdctx, env, envlen)) return 1;
  
  if(1 == EVP_DigestVerifyFinal(mdctx, sig, siglen))
  {
    return 0;
  }
  else
  {
    return 1;
  }

  return 1;
}
